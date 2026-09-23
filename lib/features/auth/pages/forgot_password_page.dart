import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';

/// A3 密码重置：成功后清会话并要求重新登录（APP-12）。
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
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
      await ref
          .read(authRepositoryProvider)
          .sendSms(phone: phone, scene: 'RESET_PASSWORD');
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
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
            phone: _phoneCtrl.text.trim(),
            code: _codeCtrl.text.trim(),
            newPassword: _pwdCtrl.text,
          );
      if (!mounted) return;
      _toast('密码已重置，请重新登录');
      context.go(RoutePath.login);
    } on ApiException catch (e) {
      _toast(e.message);
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
        title: const Text('重置密码'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePath.login),
        ),
      ),
      body: Padding(
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
                decoration: const InputDecoration(labelText: '新密码（8-64位，含字母与数字）'),
                validator: (v) {
                  final s = v ?? '';
                  if (s.length < 8 || s.length > 64) return '密码长度 8-64';
                  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
                    return '密码需同时包含字母与数字';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: const Text('重置密码'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
