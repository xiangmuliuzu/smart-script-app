import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';

/// 账号安全（规格 §8.5，契约 §1.4）。
///
/// 展示脱敏手机号与实名状态，提供换绑手机号与密码入口：
///   - 已设置密码 -> 修改密码（旧密码 + 新密码）
///   - 未设置密码 -> 首次设置密码
/// 换绑成功后后端吊销全部会话，本页要求用户用新手机号重新登录。
class AccountSecurityPage extends ConsumerWidget {
  const AccountSecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('账号安全')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is ApiException ? error.message : '加载失败，请稍后重试',
              style: const TextStyle(color: AppColors.text2),
            ),
          ),
        ),
        data: (profile) => _buildBody(context, ref, profile),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, UserProfile profile) {
    final hasPassword = ref.watch(authControllerProvider).user?.hasPassword ?? false;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              _Row(
                label: '手机号',
                value: profile.phoneMasked ?? '-',
                onTap: () => context.go(RoutePath.phoneChange),
              ),
              _Row(
                label: hasPassword ? '登录密码' : '设置密码',
                value: hasPassword ? '已设置' : '未设置',
                onTap: () => _showPasswordSheet(context, ref, hasPassword: hasPassword),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            '换绑手机号后需使用新手机号重新登录；修改密码会使其它设备的登录状态失效。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
      ],
    );
  }

  void _showPasswordSheet(BuildContext context, WidgetRef ref, {required bool hasPassword}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _PasswordSheet(hasPassword: hasPassword),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.text1))),
            Text(value, style: const TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

/// 设置/修改密码表单。与后端密码策略一致：8–64 位且同时含字母与数字。
class _PasswordSheet extends ConsumerStatefulWidget {
  const _PasswordSheet({required this.hasPassword});

  final bool hasPassword;

  @override
  ConsumerState<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends ConsumerState<_PasswordSheet> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateNew(String? value) {
    final v = value ?? '';
    if (v.length < 8 || v.length > 64) return '密码长度需为 8–64 位';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return '密码需同时包含字母与数字';
    }
    return null;
  }

  Future<void> _submit() async {
    final newPassword = _newCtrl.text;
    if (widget.hasPassword && _oldCtrl.text.isEmpty) {
      _toast('请输入当前密码');
      return;
    }
    final error = _validateNew(newPassword);
    if (error != null) {
      _toast(error);
      return;
    }
    if (newPassword != _confirmCtrl.text) {
      _toast('两次输入的新密码不一致');
      return;
    }
    setState(() => _submitting = true);
    final auth = ref.read(authControllerProvider.notifier);
    // 在异步间隙前取出 Navigator/Messenger：登出会让本页 context 失效，
    // 之后再从 context 取会触发 use_build_context_synchronously 并可能崩溃。
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (widget.hasPassword) {
        await auth.passwordChange(oldPassword: _oldCtrl.text, newPassword: newPassword);
        // 修改密码后后端吊销全部 App 会话：本地凭证立即失效，守卫回登录页。
        // 该路径不生成回跳意图（账号安全属不可恢复路径）。
        navigator.pop();
        await auth.forceLocalSignOut();
        messenger.showSnackBar(const SnackBar(content: Text('密码已修改，请重新登录')));
      } else {
        await auth.passwordSet(newPassword);
        await auth.refreshMe();
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('密码设置成功')));
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('操作失败，请稍后重试');
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.hasPassword ? '修改密码' : '设置密码',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (widget.hasPassword)
              TextField(
                controller: _oldCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前密码'),
              ),
            if (widget.hasPassword) const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}
