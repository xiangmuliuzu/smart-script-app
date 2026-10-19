import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_form.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 申请成为创作者（契约 §1.6）。
///
/// 状态机：NOT_SUBMITTED -> PENDING -> APPROVED；PENDING -> REJECTED -> PENDING。
/// 审核中不可重复提交，已通过（已是创作者）不可再申请；驳回后可重新提交。
/// 审核通过由后台运维端完成，通过后自动开通作者能力。
class CreatorApplyPage extends ConsumerWidget {
  const CreatorApplyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(creatorApplyStatusProvider);

    return statusAsync.when(
      loading: () => const UserCenterScaffold(
        title: '成为创作者',
        body: LoadingView(message: '加载中'),
      ),
      error: (error, _) => UserCenterScaffold(
        title: '成为创作者',
        body: ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(creatorApplyStatusProvider),
        ),
      ),
      data: (status) => _CreatorApplyBody(status: status),
    );
  }
}

class _CreatorApplyBody extends ConsumerStatefulWidget {
  const _CreatorApplyBody({required this.status});

  final CreatorApplyStatus status;

  @override
  ConsumerState<_CreatorApplyBody> createState() => _CreatorApplyBodyState();
}

class _CreatorApplyBodyState extends ConsumerState<_CreatorApplyBody> {
  final _penNameCtrl = TextEditingController();
  final _directionCtrl = TextEditingController();
  final _portfolioCtrl = TextEditingController();
  final _introCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _submitting = false;
  CreatorApplyStatus? _submittedStatus;

  // 与后端 DTO / 列宽一致的长度上限，本地先拦截。
  static const int _penNameMax = 50;
  static const int _directionMax = 200;
  static const int _portfolioMax = 500;
  static const int _introMax = 500;
  static const int _contactMax = 100;

  @override
  void dispose() {
    _penNameCtrl.dispose();
    _directionCtrl.dispose();
    _portfolioCtrl.dispose();
    _introCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final status = _submittedStatus ?? widget.status;
    if (_submitting || !status.state.canSubmit) return;
    final penName = _penNameCtrl.text.trim();
    final direction = _directionCtrl.text.trim();
    final portfolio = _portfolioCtrl.text.trim();
    final intro = _introCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    if (penName.isEmpty || penName.length > _penNameMax) {
      _toast('请输入 1–$_penNameMax 个字符的笔名');
      return;
    }
    if (direction.isEmpty || direction.length > _directionMax) {
      _toast('请填写创作方向（不超过 $_directionMax 字）');
      return;
    }
    if (portfolio.length > _portfolioMax) {
      _toast('代表作品不超过 $_portfolioMax 字');
      return;
    }
    if (intro.isEmpty || intro.length > _introMax) {
      _toast('请填写申请说明（不超过 $_introMax 字）');
      return;
    }
    if (contact.isEmpty || contact.length > _contactMax) {
      _toast('请填写联系方式（不超过 $_contactMax 字）');
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await ref.read(userCenterRepositoryProvider).submitCreatorApply(
            penName: penName,
            direction: direction,
            portfolio: portfolio,
            intro: intro,
            contact: contact,
          );
      if (!mounted) return;
      setState(() => _submittedStatus = result);
      _toast('提交成功，请等待审核');
      // 提交已成功，身份摘要暂刷新失败不应误报申请失败。
      try {
        await ref.read(authControllerProvider.notifier).refreshMe();
      } catch (_) {}
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('提交失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final status = _submittedStatus ?? widget.status;
    return UserCenterScaffold(
      title: '成为创作者',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _StatusCard(status: status),
          if (status.state.canSubmit) ...[
            const SizedBox(height: 12),
            _buildForm(status),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Text(
                status.state == CreatorApplyState.pending
                    ? '申请审核中，暂不能重复提交。'
                    : '您已成为创作者，无需重复申请。',
                style: const TextStyle(color: AppColors.text3, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: status.state.canSubmit
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: UserPrimaryButton(
                  label: status.state == CreatorApplyState.rejected
                      ? '重新提交'
                      : '提交申请',
                  onPressed: _submitting ? null : _submit,
                  busy: _submitting,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildForm(CreatorApplyStatus status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.state == CreatorApplyState.rejected)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
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
        UserFormCard(
          children: [
            UserFormField(
              label: '笔名',
              child: UserPlainTextField(
                controller: _penNameCtrl,
                enabled: !_submitting,
                maxLength: _penNameMax,
                hint: '展示给读者的笔名',
              ),
            ),
            UserFormField(
              label: '创作方向',
              child: UserPlainTextField(
                controller: _directionCtrl,
                enabled: !_submitting,
                maxLength: _directionMax,
                hint: '如 都市/悬疑/言情',
              ),
            ),
            UserFormField(
              label: '代表作品',
              child: UserPlainTextField(
                controller: _portfolioCtrl,
                enabled: !_submitting,
                maxLength: _portfolioMax,
                hint: '选填，作品名称或链接',
              ),
            ),
            UserFormField(
              label: '申请说明',
              child: UserPlainTextField(
                controller: _introCtrl,
                enabled: !_submitting,
                maxLength: _introMax,
                maxLines: 3,
                hint: '简单介绍你的创作经历与计划',
              ),
            ),
            UserFormField(
              label: '联系方式',
              showDivider: false,
              child: UserPlainTextField(
                controller: _contactCtrl,
                enabled: !_submitting,
                maxLength: _contactMax,
                hint: '手机号/微信，便于审核联系',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            '提交后由平台运营审核，审核通过即开通创作者能力。请如实填写，信息将用于审核联系。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final CreatorApplyStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.r)),
        boxShadow: AppColors.cardShadow,
      ),
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
          if (status.penName != null)
            UserInfoLine(label: '笔名', value: status.penName!),
          if (status.direction != null)
            UserInfoLine(label: '创作方向', value: status.direction!),
          if (status.portfolio != null && status.portfolio!.isNotEmpty)
            UserInfoLine(label: '代表作品', value: status.portfolio!),
          if (status.contact != null)
            UserInfoLine(label: '联系方式', value: status.contact!),
          if (status.submittedAt != null)
            UserInfoLine(label: '提交时间', value: status.submittedAt!),
          if (status.reviewedAt != null)
            UserInfoLine(label: '审核时间', value: status.reviewedAt!),
          if (status.state == CreatorApplyState.rejected &&
              status.rejectReason != null)
            UserInfoLine(label: '驳回原因', value: status.rejectReason!),
        ],
      ),
    );
  }

  Color get _color {
    switch (status.state) {
      case CreatorApplyState.approved:
        return AppColors.success;
      case CreatorApplyState.pending:
        return AppColors.warning;
      case CreatorApplyState.rejected:
        return AppColors.danger;
      case CreatorApplyState.notSubmitted:
        return AppColors.text3;
    }
  }

  IconData get _icon {
    switch (status.state) {
      case CreatorApplyState.approved:
        return Icons.verified;
      case CreatorApplyState.pending:
        return Icons.hourglass_empty;
      case CreatorApplyState.rejected:
        return Icons.error_outline;
      case CreatorApplyState.notSubmitted:
        return Icons.info_outline;
    }
  }
}
