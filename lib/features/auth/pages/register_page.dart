import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';

/// A3 注册页：手机号 + 验证码 + 密码 + 协议（服务端校验当前版本）。
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _agree = false;
  bool _loading = false;
  int _cooldown = 0;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendSms() async {
    final phone = _phoneCtrl.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      _toast('请输入正确的手机号');
      return;
    }
    if (_cooldown > 0) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).sendSms(phone: phone, scene: 'REGISTER');
      if (!mounted) return;
      setState(() => _cooldown = 60);
      Future.doWhile(() async {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return false;
        setState(() => _cooldown -= 1);
        return _cooldown > 0;
      });
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agree) {
      _toast('请先同意用户协议与隐私政策');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            phone: _phoneCtrl.text.trim(),
            code: _codeCtrl.text.trim(),
            password: _pwdCtrl.text,
          );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('注册失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('注册'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePath.login),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '手机号'),
                  validator: (v) =>
                      RegExp(r'^1\d{10}$').hasMatch((v ?? '').trim()) ? null : '请输入 11 位手机号',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '验证码'),
                        validator: (v) => (v ?? '').trim().length >= 4 ? null : '请输入验证码',
                      ),
                    ),
                    TextButton(
                      onPressed: _cooldown > 0 || _loading ? null : _sendSms,
                      child: Text(_cooldown > 0 ? '${_cooldown}s' : '获取验证码'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码（8-64位，含字母与数字）'),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.length < 8 || s.length > 64) return '密码长度 8-64';
                    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
                      return '密码需同时包含字母与数字';
                    }
                    return null;
                  },
                ),
                CheckboxListTile(
                  value: _agree,
                  onChanged: (v) => setState(() => _agree = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('我已阅读并同意《用户协议》与《隐私政策》', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('注册并登录'),
                ),
                TextButton(
                  onPressed: () => context.go(RoutePath.login),
                  child: const Text('已有账号？去登录'),
                ),
                const SizedBox(height: 8),
                const Text(
                  '协议版本由服务端 /auth/agreements 下发；自动注册须提交当前两类协议。',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
