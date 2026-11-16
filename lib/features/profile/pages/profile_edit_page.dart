import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/services/native_image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/avatar_url.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_form.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../../user_center/widgets/user_center_widgets.dart';

/// 个人资料（规格 §8.3，契约 §1.2）。
///
/// 头像选定后立即上传并保存，无需再点底部「保存」；
/// 昵称与简介仍由底部「保存」按钮统一提交。
/// 手机号、角色、实名状态为只读展示。
/// 保存成功后刷新全局 currentUser，使其它页面立即显示新资料。
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _nicknameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _uploading = false;

  /// 已上传待保存的头像地址；为空表示本次未修改头像。
  String? _pendingAvatar;
  String? _loadedAvatar;

  /// 进入页面时的昵称原文，用于判断本次是否真的改动了昵称。
  String _initialNickname = '';

  /// 进入页面时的简介原文；简介可清空，因此用「是否改过」而不是「是否为空」判断。
  String _initialBio = '';

  /// 与后端用户名称/简介上限一致的本地预校验上限。
  static const int _nicknameMax = 15;
  static const int _bioMax = 200;

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _uploading) return;
    final nickname = _nicknameCtrl.text.trim();
    if (nickname.isEmpty) {
      _toast('用户名称不能为空');
      return;
    }
    if (nickname.runes.length > _nicknameMax) {
      _toast('用户名称不能超过 $_nicknameMax 个字符');
      return;
    }
    final bio = _bioCtrl.text.trim();
    if (bio.length > _bioMax) {
      _toast('简介不能超过 $_bioMax 个字符');
      return;
    }
    final avatarChanged = _pendingAvatar != null && _pendingAvatar != _loadedAvatar;
    final nicknameChanged = nickname != _initialNickname;
    // 简介允许清空：内容与初始值不同即视为改动（含清空为空串）
    final bioChanged = bio != _initialBio.trim();
    if (!avatarChanged && !nicknameChanged && !bioChanged) {
      _toast('没有需要保存的修改');
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await ref.read(userCenterRepositoryProvider).updateProfile(
            nickname: nicknameChanged ? nickname : null,
            avatar: avatarChanged ? _pendingAvatar : null,
            bio: bioChanged ? bio : null,
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
        _bioCtrl.text = profile.bio ?? '';
        _initialBio = _bioCtrl.text;
      });
      _toast('保存成功');
    } on ApiException catch (e) {
      _toast(e.message);
      return;
    } catch (_) {
      _toast('保存失败，请稍后重试');
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // 保存成功：退出编辑页。放在 try/catch 之外，避免导航异常被当成保存失败吞掉。
    if (mounted) _pop();
  }

  /// 选择头像后立即上传并保存，不依赖底部「保存」按钮。
  ///
  /// 上传得到站内路径后直接落库并刷新全局 currentUser，各页面即时生效；
  /// 只改头像，不影响昵称/简介未保存的编辑内容。
  Future<void> _changeAvatar() async {
    if (_uploading || _saving) return;
    setState(() => _uploading = true);
    try {
      final picked = await NativeImagePicker.pickImage();
      if (picked == null || !mounted) return; // 用户取消选择
      final url = await ref.read(userCenterRepositoryProvider).uploadAvatar(
            bytes: picked.bytes,
            filename: picked.filename,
          );
      if (!mounted) return;
      if (url == _loadedAvatar) {
        // 与当前头像一致，无需落库
        setState(() => _pendingAvatar = url);
        _toast('头像未变化');
        return;
      }
      final profile = await ref.read(userCenterRepositoryProvider).updateProfile(
            avatar: url,
          );
      // 刷新全局 currentUser，所有页面立即显示新头像（规格 §8.3）
      await ref.read(authControllerProvider.notifier).refreshMe();
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      setState(() {
        _loadedAvatar = profile.avatar;
        _pendingAvatar = profile.avatar;
      });
      _toast('头像已更新');
    } on NativeImageException catch (e) {
      _toast(e.message);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('头像更新失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 是否还有未保存的改动。
  ///
  /// 保存成功后会先把本地基线同步到服务端返回值，因此这里能立即反映「已无改动」，
  /// 用于无改动返回时静默退出而不是弹「是否放弃」。
  bool get _hasUnsavedChanges {
    final avatarChanged = _pendingAvatar != null && _pendingAvatar != _loadedAvatar;
    return avatarChanged ||
        _nicknameCtrl.text.trim() != _initialNickname ||
        _bioCtrl.text.trim() != _initialBio.trim();
  }

  /// 返回上一页（AppBar 返回键与系统返回键共用）。
  ///
  /// 有未保存改动时二次确认，避免误触丢失编辑内容。
  Future<void> _onBack() async {
    if (!_hasUnsavedChanges) {
      _pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃修改'),
        content: const Text('当前修改尚未保存，确定要离开吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) _pop();
  }

  /// 关闭本页。
  ///
  /// 关闭动作放在 `finally` 之外执行，确保它抛出的任何导航异常都不会被
  /// 「保存失败」的兜底 catch 静默吞掉，导致页面看起来像没退出。
  void _pop() {
    if (!mounted) return;
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      // 写入根定位（而不是相对子路径），确保能从任何深度的导航栈回到「我的」。
      router.go(RoutePath.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _onBack();
      },
      child: UserCenterScaffold(
        title: '个人资料',
        // 返回键走统一出口：有未保存改动先确认。
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBack,
        ),
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
            _bioCtrl.text = profile.bio ?? '';
            _initialBio = _bioCtrl.text;
          }
          return _buildForm(profile);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: UserPrimaryButton(
            label: '保存',
            onPressed: _saving || _uploading ? null : _save,
            busy: _saving,
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildForm(UserProfile profile) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // 头像区不铺白底，直接浮在页面顶部渐变上。
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _saving || _uploading ? null : _changeAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      ClipOval(
                        child: Container(
                          // 头像外描一圈白边，在渐变背景上有清晰的落位。
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.card, width: 2),
                          ),
                          child: SizedBox(
                            width: 80,
                            height: 80,
                            child: ClipOval(
                              child: (_pendingAvatar != null && _pendingAvatar!.isNotEmpty)
                                  ? Image.network(
                                      avatarUrl(_pendingAvatar),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const _AvatarFallback(),
                                    )
                                  : const _AvatarFallback(),
                            ),
                          ),
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
        // 可编辑资料：用户名称 + 简介。
        UserFormCard(
          children: [
            UserFormField(
              label: '用户名称',
              child: UserPlainTextField(
                controller: _nicknameCtrl,
                enabled: !_saving,
                hint: '请输入用户名称',
                maxLength: _nicknameMax,
              ),
            ),
            UserFormField(
              label: '简介',
              child: UserPlainTextField(
                controller: _bioCtrl,
                enabled: !_saving,
                hint: '介绍一下自己（可留空）',
                maxLength: _bioMax,
                maxLines: 3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 只读信息：手机号 + 实名状态。无底部分隔线，卡片自带留白收尾。
        UserFormCard(
          children: [
            UserFormField(
              label: '手机号',
              child: _FieldValue(text: profile.phoneMasked ?? '-'),
            ),
            UserFormField(
              label: '实名状态',
              showDivider: false,
              child: _RealNameValue(
                state: RealNameState.fromCode(profile.realNameStatus),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            '用户名称用于页面展示，不能重复，长度为 1–$_nicknameMax 个字符。简介可留空或清空，最长 $_bioMax 个字符；手机号与实名状态需在账号安全、实名认证中单独办理，不能在此修改。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 只读值：与输入框相同的字号与字重，视觉上作为同一列内容。
class _FieldValue extends StatelessWidget {
  const _FieldValue({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.text1,
      ),
    );
  }
}

/// 实名状态：已通过时显示绿色小标签，其余状态显示为普通文本。
class _RealNameValue extends StatelessWidget {
  const _RealNameValue({required this.state});

  final RealNameState state;

  @override
  Widget build(BuildContext context) {
    final color = _color(state);
    if (state == RealNameState.approved) {
      return Align(
        alignment: Alignment.centerLeft,
        child: UserStatusChip(text: state.label, color: color),
      );
    }
    return Text(
      state.label,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color),
    );
  }

  Color _color(RealNameState state) {
    switch (state) {
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
