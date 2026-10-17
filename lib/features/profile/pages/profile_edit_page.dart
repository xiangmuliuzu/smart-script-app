import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/services/native_image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/avatar_url.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
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
      if (mounted) context.pop();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            _bioCtrl.text = profile.bio ?? '';
            _initialBio = _bioCtrl.text;
          }
          return _buildForm(profile);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _SaveButton(
            onPressed: _saving || _uploading ? null : _save,
            busy: _saving,
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
        _FormCard(
          children: [
            _Field(
              label: '用户名称',
              child: _PlainTextField(
                controller: _nicknameCtrl,
                enabled: !_saving,
                hint: '请输入用户名称',
                maxLength: _nicknameMax,
              ),
            ),
            _Field(
              label: '简介',
              child: _PlainTextField(
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
        _FormCard(
          children: [
            _Field(
              label: '手机号',
              child: _FieldValue(text: profile.phoneMasked ?? '-'),
            ),
            _Field(
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

/// 圆角白色分组卡片：去掉全屏通栏分割线后，页面内容以卡片分组呈现。
class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.r)),
        boxShadow: AppColors.cardShadow,
      ),
      // 上下统一 4 的呼吸感，行与行之间由 _Field 自带的内边距撑开。
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    );
  }
}

/// 表单行：左侧固定宽度标签 + 右侧左对齐内容。
///
/// 输入框与只读值共用同一套 [padding] 与标签宽度，保证「用户名称」「简介」
/// 的输入起点与下方「手机号」完全对齐。
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.showDivider = true,
  });

  final String label;
  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Padding(
              // 与右侧单行文本的首行基线对齐。
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: AppColors.text2),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 无边框透明输入框：去掉外描边与默认填充，文字下沉到卡片内。
class _PlainTextField extends StatelessWidget {
  const _PlainTextField({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.maxLength,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final int maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      minLines: 1,
      maxLength: maxLength,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.text1,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        // 主题里给输入框统一加了填充与描边，这里显式清空。
        fillColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.placeholder,
        ),
      ),
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

/// 底部保存按钮：深主色实心胶囊，带主色投影。
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: BorderRadius.circular(24),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x331E4078),
                    offset: Offset(0, 6),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
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
