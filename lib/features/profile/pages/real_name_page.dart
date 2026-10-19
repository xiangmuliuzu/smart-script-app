import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/services/native_image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 实名认证（规格 §8.4，契约 §1.3）。
///
/// 状态机：NOT_SUBMITTED -> PENDING -> APPROVED；PENDING -> REJECTED -> PENDING。
/// 审核中不可重复提交，已通过不可自行覆盖；驳回后可重新提交。
/// 身份证号只以掩码展示，材料通过平台上传服务提交引用。
class RealNamePage extends ConsumerWidget {
  const RealNamePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(realNameStatusProvider);

    return UserCenterScaffold(
      title: '实名认证',
      actions: null,
      body: statusAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(realNameStatusProvider),
        ),
        data: (status) => _RealNameBody(status: status),
      ),
    );
  }
}

class _RealNameBody extends ConsumerStatefulWidget {
  const _RealNameBody({required this.status});

  final RealNameStatus status;

  @override
  ConsumerState<_RealNameBody> createState() => _RealNameBodyState();
}

class _RealNameBodyState extends ConsumerState<_RealNameBody> {
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  PickedImage? _materialImage;
  MemoryImage? _previewImage;
  String? _materialRef;
  String? _uploadError;
  bool _uploading = false;
  bool _picking = false;
  bool _submitting = false;
  RealNameStatus? _submittedStatus;

  bool get _busy => _submitting || _uploading || _picking;

  /// 与后端校验一致的身份证号形态（15 位旧证 / 18 位新证，末位可为 X）。
  static final RegExp _idPattern = RegExp(r'^\d{15}$|^\d{17}[0-9Xx]$');

  @override
  void dispose() {
    _clearMaterialPreview();
    _nameCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_submittedStatus ?? widget.status).state.canSubmit) return;
    final realName = _nameCtrl.text.trim();
    final idNumber = _idCtrl.text.trim();
    if (realName.length < 2 || realName.length > 32) {
      _toast('请输入 2–32 个字符的真实姓名');
      return;
    }
    if (!_idPattern.hasMatch(idNumber)) {
      _toast('请输入正确的身份证号');
      return;
    }
    final material = _materialRef;
    if (material == null) {
      _toast('请先上传证件照片');
      return;
    }
    final resubmit = widget.status.state == RealNameState.rejected;
    setState(() => _submitting = true);
    try {
      final result =
          await ref.read(userCenterRepositoryProvider).submitRealName(
                realName: realName,
                idNumber: idNumber,
                materialRefs: [material],
                resubmit: resubmit,
              );
      if (!mounted) return;
      setState(() {
        _submittedStatus = result;
        if (result.state != RealNameState.rejected) {
          _clearMaterialPreview();
          _materialRef = null;
          _uploadError = null;
        }
      });
      _toast(switch (result.state) {
        RealNameState.approved => '实名认证通过',
        RealNameState.rejected => '实名认证未通过，请核对后重新提交',
        _ => '提交成功，请等待审核',
      });
      if (result.state != RealNameState.rejected) {
        _nameCtrl.clear();
        _idCtrl.clear();
      }
      // 提交已经成功，身份摘要暂时刷新失败不应误报申请失败。
      try {
        await ref.read(authControllerProvider.notifier).refreshMe();
      } catch (_) {}
      // 页面使用提交响应展示核验结果；离开后 autoDispose，重进再查询最新状态。
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('提交失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickMaterial() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _picking = true);
    try {
      final image =
          await NativeImagePicker.pickImage(filenamePrefix: 'realname');
      if (image == null || !mounted) return;
      setState(() {
        _clearMaterialPreview();
        _materialImage = image;
        _previewImage = MemoryImage(Uint8List.fromList(image.bytes));
        _materialRef = null;
        _uploadError = null;
      });
      await _uploadMaterial();
    } on NativeImageException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('无法选择图片，请重试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _uploadMaterial() async {
    final image = _materialImage;
    if (image == null || _uploading || _submitting) return;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final reference =
          await ref.read(userCenterRepositoryProvider).uploadRealNameMaterial(
                bytes: image.bytes,
                filename: image.filename,
              );
      if (mounted) setState(() => _materialRef = reference);
    } on ApiException catch (e) {
      if (mounted) setState(() => _uploadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _uploadError = '上传失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeMaterial() {
    if (_busy) return;
    setState(() {
      _clearMaterialPreview();
      _materialRef = null;
      _uploadError = null;
    });
  }

  void _clearMaterialPreview() {
    unawaited(_previewImage?.evict());
    _previewImage = null;
    _materialImage = null;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final status = _submittedStatus ?? widget.status;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _StatusCard(status: status),
        if (status.state.canSubmit) ...[
          const SizedBox(height: 12),
          _buildForm(status),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              status.state == RealNameState.pending
                  ? '申请审核中，暂不能重复提交。'
                  : '已通过实名认证，如需变更请联系客服。',
              style: const TextStyle(color: AppColors.text3, fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildForm(RealNameStatus status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.state == RealNameState.rejected)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '上次驳回原因：${status.rejectReason ?? '未填写'}\n可修改后重新提交。',
              style: const TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ),
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              UserFieldRow(
                label: '真实姓名',
                child: TextField(
                  controller: _nameCtrl,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '与证件一致',
                  ),
                ),
              ),
              UserFieldRow(
                label: '身份证号',
                child: TextField(
                  controller: _idCtrl,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '15 或 18 位',
                  ),
                ),
              ),
              UserFieldRow(
                label: '证件材料',
                child: _buildMaterialPicker(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    status.state == RealNameState.rejected ? '重新提交' : '提交认证'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            '请上传清晰、完整的证件照片，用于实名认证审核。支持 JPG、PNG、GIF、BMP，每张不超过 5 MB。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialPicker() {
    final image = _materialImage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (image != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              image: _previewImage!,
              height: 140,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 100,
                child: Center(child: Icon(Icons.image_outlined, size: 40)),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_uploading || _picking && image == null)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('正在上传…'),
            ],
          )
        else if (_uploadError != null)
          Text(_uploadError!, style: const TextStyle(color: AppColors.danger))
        else if (_materialRef != null)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  color: AppColors.success, size: 18),
              SizedBox(width: 6),
              Text('上传成功', style: TextStyle(color: AppColors.success)),
            ],
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickMaterial,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(image == null ? '选择证件照片' : '更换照片'),
        ),
        if (image != null)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (_uploadError != null)
                TextButton(
                    onPressed: _busy ? null : _uploadMaterial,
                    child: const Text('重试上传')),
              TextButton(
                  onPressed: _busy ? null : _removeMaterial,
                  child: const Text('移除照片')),
            ],
          ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final RealNameStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _color, size: 20),
              const SizedBox(width: 8),
              Text(
                status.state.label,
                style: TextStyle(
                    color: _color, fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (status.realNameMasked != null)
            UserInfoLine(label: '姓名', value: status.realNameMasked!),
          if (status.idNumberMasked != null)
            UserInfoLine(label: '证件号', value: status.idNumberMasked!),
          if (status.submittedAt != null)
            UserInfoLine(label: '提交时间', value: status.submittedAt!),
          if (status.reviewedAt != null)
            UserInfoLine(label: '审核时间', value: status.reviewedAt!),
          if (status.state == RealNameState.rejected &&
              status.rejectReason != null)
            UserInfoLine(label: '驳回原因', value: status.rejectReason!),
        ],
      ),
    );
  }

  Color get _color {
    switch (status.state) {
      case RealNameState.approved:
        return AppColors.success;
      case RealNameState.pending:
        return AppColors.warning;
      case RealNameState.rejected:
        return AppColors.danger;
      case RealNameState.notSubmitted:
        return AppColors.text3;
    }
  }

  IconData get _icon {
    switch (status.state) {
      case RealNameState.approved:
        return Icons.verified;
      case RealNameState.pending:
        return Icons.hourglass_empty;
      case RealNameState.rejected:
        return Icons.error_outline;
      case RealNameState.notSubmitted:
        return Icons.info_outline;
    }
  }
}
