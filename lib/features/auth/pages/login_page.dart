import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/theme/app_colors.dart';

/// 登录页（接口文档 2.1.3）。
///
/// 这是框架层给出的**可运行参考实现**：演示如何调用 AuthController.login、
/// 如何处理统一异常、如何触发全局登录态刷新（成功后 redirect 自动进首页）。
/// 登录注册负责人可在此基础上补齐：验证码登录、注册跳转、找回密码、第三方登录等。
/// 登录按钮下方的“测试进入”为免登录调试入口，直达书城，正式接入后可删除。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_phoneCtrl.text.trim(), _pwdCtrl.text);
      // 登录成功后 redirect 会自动跳转到首页，无需手动导航。
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('登录失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 免登录测试入口：置为已登录后 redirect 自动进书城，无需手动导航。
  void _enterTest() {
    ref.read(authControllerProvider.notifier).enterTestSession();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 64),
                const Text(
                  '欢迎回来',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '手机号'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入手机号';
                    if (v.trim().length != 11) return '手机号应为 11 位';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: '密码'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? '请输入密码' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('登录'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : _enterTest,
                  child: const Text('测试进入（免登录，直达书城）'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
