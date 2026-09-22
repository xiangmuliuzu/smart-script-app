import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';

/// A3 登录页：密码登录 + 验证码登录。无免登录入口。
///
/// A5：登录成功后消费一次守卫保存的回跳意图（规格 §8.1）。
/// 意图不存在、参数非法或目标不允许恢复时进入安全默认首页并提示。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _useSms = false;
  int _cooldown = 0;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pwdCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final phone = _phoneCtrl.text.trim();
      final auth = ref.read(authControllerProvider.notifier);
      if (_useSms) {
        await auth.loginWithSms(phone: phone, code: _codeCtrl.text.trim());
      } else {
        await auth.loginWithPassword(phone, _pwdCtrl.text);
      }
      if (!mounted) return;
      _resolvePostLoginTarget();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('登录失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 登录成功后的去向：消费一次回跳意图，否则回安全默认首页。
  ///
  /// 取消登录、登录失败与网络错误都不会走到这里，因此意图被保留到下一次成功登录；
  /// 成功登录才消费，保证同一个意图只回跳一次。
  void _resolvePostLoginTarget() {
    final target = AuthGuard.consumeAndResolve(ref);
    if (target == null) {
      context.go(RoutePath.home);
      return;
    }
    context.go(target);
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
      await ref.read(authRepositoryProvider).sendSms(phone: phone, scene: 'LOGIN');
      if (!mounted) return;
      setState(() => _cooldown = 60);
      _toast('验证码已发送');
      Future.doWhile(() async {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return false;
        setState(() => _cooldown -= 1);
        return _cooldown > 0;
      });
    } on ApiException catch (e) {
      final retry = e.data is Map ? (e.data as Map)['retryAfterSeconds'] : null;
      if (retry is num) setState(() => _cooldown = retry.toInt());
      _toast(e.message);
    } catch (_) {
      _toast('发送失败，请稍后重试');
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 48),
                const Text(
                  '欢迎回来',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _useSms ? '使用验证码登录' : '使用密码登录',
                  style: const TextStyle(color: AppColors.text3),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '手机号'),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (!RegExp(r'^1\d{10}$').hasMatch(s)) {
                      return '请输入 11 位手机号';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (!_useSms)
                  TextFormField(
                    controller: _pwdCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码'),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return '请输入密码';
                      return null;
                    },
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '验证码'),
                          validator: (v) {
                            if ((v ?? '').trim().length < 4) return '请输入验证码';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _cooldown > 0 || _loading ? null : _sendSms,
                        child: Text(_cooldown > 0 ? '${_cooldown}s' : '获取验证码'),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
                TextButton(
                  onPressed: () {
                    if (mounted) {
                      setState(() => _useSms = !_useSms);
                    }
                  },
                  child: Text(_useSms ? '改用密码登录' : '改用验证码登录'),
                ),
                TextButton(
                  onPressed: () => context.go(RoutePath.register),
                  child: const Text('没有账号？去注册'),
                ),
                TextButton(
                  onPressed: () => context.go(RoutePath.forgotPassword),
                  child: const Text('忘记密码'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
