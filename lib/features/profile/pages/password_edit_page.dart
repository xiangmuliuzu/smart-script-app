import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 设置 / 修改登录密码（规格 §8.5）。
///
/// 已设置密码 -> 修改密码（旧密码 + 新密码）；未设置 -> 首次设置密码。
///
/// 为什么是独立页面而不是底部弹窗：
///   1. 弹窗在软键盘弹出后命中区域错位，实测点击输入框下方的「确定」会被
///      判定为点击遮罩而关闭弹窗（人工冒烟中无法完成提交流程）；
///   2. 密码修改会吊销全部会话，属于需要明确确认的敏感操作，独立页面的
///      确认语义比弹窗更清晰。
class PasswordEditPage extends ConsumerStatefulWidget {
  const PasswordEditPage({super.key, required this.hasPassword});

  /// 是否已设置密码，由账号安全页按 /auth/me 的 hasPassword 传入。
  final bool hasPassword;

  @override
  ConsumerState<PasswordEditPage> createState() => _PasswordEditPageState();
}

class _PasswordEditPageState extends ConsumerState<PasswordEditPage> {
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validateNew(String value) {
    if (value.length < 8 || value.length > 64) return '密码长度需为 8–64 位';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
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
    try {
      if (widget.hasPassword) {
        await auth.passwordChange(oldPassword: _oldCtrl.text, newPassword: newPassword);
        // 修改密码后后端吊销全部 App 会话：本地凭证立即失效。
        // 安全底线：该路径不生成回跳意图，用户需重新登录。
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        await auth.forceLocalSignOut();
        messenger.showSnackBar(const SnackBar(content: Text('密码已修改，请重新登录')));
      } else {
        await auth.passwordSet(newPassword);
        await auth.refreshMe();
        if (!mounted) return;
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码设置成功')));
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 提交按钮放在页面底部（ListView 之外），并由 SafeArea 让它随软键盘上移：
    // 若把按钮放在可滚动列表里，键盘弹出后列表可视区被压缩，按钮会落到键盘之后，
    // 需要先滚动才能点到（人工冒烟中即因此无法完成提交）。
    return UserCenterScaffold(
      title: widget.hasPassword ? '修改密码' : '设置密码',
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确定'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (widget.hasPassword) ...[
                  TextField(
                    controller: _oldCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '当前密码'),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _newCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '新密码（8–64 位，含字母与数字）'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: '确认新密码'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              widget.hasPassword
                  ? '修改密码后，所有设备上的登录状态都会失效，需要用新密码重新登录。'
                  : '设置密码后可使用手机号 + 密码登录。',
              style: const TextStyle(color: Color(0xFF86909C), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
