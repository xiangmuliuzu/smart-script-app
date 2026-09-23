import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/services/native_image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 个人资料（规格 §8.3，契约 §1.2）。
///
/// 只允许修改头像与昵称；手机号、角色、实名状态为只读展示。
/// 保存成功后刷新全局 currentUser，使其它页面立即显示新资料。
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _nicknameCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _uploading = false;

  /// 已上传待保存的头像地址；为空表示本次未修改头像。
  String? _pendingAvatar;
  String? _loadedAvatar;

  /// 进入页面时的昵称原文，用于判断本次是否真的改动了昵称。
  String _initialNickname = '';

  /// 与后端昵称列宽一致的本地预校验上限。
  static const int _nicknameMax = 30;

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nickname = _nicknameCtrl.text.trim();
    if (nickname.isEmpty) {
      _toast('昵称不能为空');
      return;
    }
    if (nickname.length > _nicknameMax) {
      _toast('昵称不能超过 $_nicknameMax 个字符');
      return;
    }
    final avatarChanged = _pendingAvatar != null && _pendingAvatar != _loadedAvatar;
    final nicknameChanged = nickname != _initialNickname;
    if (!avatarChanged && !nicknameChanged) {
      _toast('没有需要保存的修改');
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await ref.read(userCenterRepositoryProvider).updateProfile(
            nickname: nicknameChanged ? nickname : null,
            avatar: avatarChanged ? _pendingAvatar : null,
          );
      // 刷新全局 currentUser，所有页面立即显示新资料（规格 §8.3）
      await ref.read(authControllerProvider.notifier).refreshMe();
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      setState(() {
        _loadedAvatar = profile.avatar;
        _pendingAvatar = profile.avatar;
        _nicknameCtrl.text = profile.nickname ?? nickname;
        _initialNickname = _nicknameCtrl.text;
      });
      _toast('保存成功');
      if (mounted) context.pop();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final picked = await NativeImagePicker.pickImage();
      if (picked == null) return;
      final url = await ref.read(userCenterRepositoryProvider).uploadAvatar(
            bytes: picked.bytes,
            filename: picked.filename,
          );
      if (!mounted) return;
      setState(() => _pendingAvatar = url);
      _toast('头像已上传，保存后生效');
    } on NativeImageException catch (e) {
      _toast(e.message);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('头像上传失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return UserCenterScaffold(
        title: '个人资料',
        actions: null,
        body: profileAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(userProfileProvider),
        ),
        data: (profile) {
          if (!_initialized) {
            _initialized = true;
            _nicknameCtrl.text = profile.nickname ?? '';
            _initialNickname = _nicknameCtrl.text;
            _loadedAvatar = profile.avatar;
            _pendingAvatar = profile.avatar;
          }
          return _buildForm(profile);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _saving || _uploading ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(UserProfile profile) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 84,
                          height: 84,
                          child: (_pendingAvatar != null && _pendingAvatar!.isNotEmpty)
                              ? Image.network(
                                  _pendingAvatar!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const _AvatarFallback(),
                                )
                              : const _AvatarFallback(),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _uploading ? '上传中…' : '点击更换头像',
                  style: const TextStyle(color: AppColors.text3, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              _Field(
                label: '昵称',
                child: TextField(
                  controller: _nicknameCtrl,
                  maxLength: _nicknameMax,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    hintText: '请输入昵称',
                  ),
                ),
              ),
              _Field(
                label: '手机号',
                child: Text(
                  profile.phoneMasked ?? '-',
                  style: const TextStyle(color: AppColors.text3),
                ),
              ),
              _Field(
                label: '实名状态',
                child: Text(
                  RealNameState.fromCode(profile.realNameStatus).label,
                  style: const TextStyle(color: AppColors.text3),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            '手机号与实名状态需在账号安全、实名认证中单独办理，不能在此修改。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(color: AppColors.text2)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.fill,
      child: const Icon(Icons.account_circle, size: 48, color: AppColors.text3),
    );
  }
}
