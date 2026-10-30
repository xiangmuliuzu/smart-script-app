import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/utils/auth_validators.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 先验证已绑定的账号，再验证新邮箱；成功后重新登录。
class EmailChangePage extends ConsumerStatefulWidget {
  const EmailChangePage({super.key});

  @override
  ConsumerState<EmailChangePage> createState() => _EmailChangePageState();
}

class _EmailChangePageState extends ConsumerState<EmailChangePage> {
  final _oldCodeCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();
  final _newCodeCtrl = TextEditingController();

  int _step = 1;
  bool _busy = false;
  int _oldCooldown = 0;
  int _newCooldown = 0;

  /// 旧号验证凭证：只在本次换绑流程的内存中保存。
  String? _stepUpToken;

  @override
  void dispose() {
    _oldCodeCtrl.dispose();
    _newEmailCtrl.dispose();
    _newCodeCtrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _startCooldown({required bool oldPhone}) {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        if (oldPhone) {
          _oldCooldown -= 1;
        } else {
          _newCooldown -= 1;
        }
      });
      return oldPhone ? _oldCooldown > 0 : _newCooldown > 0;
    });
  }

  Future<void> _sendOldCode() async {
    if (_oldCooldown > 0 || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(userCenterRepositoryProvider).sendOldPhoneCode();
      if (!mounted) return;
      setState(() => _oldCooldown = 60);
      _startCooldown(oldPhone: true);
      _toast('验证码已发送至当前手机号或邮箱');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('发送失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOldCode() async {
    final code = _oldCodeCtrl.text.trim();
    if (code.isEmpty) {
      _toast('请输入收到的验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final stepUp =
          await ref.read(userCenterRepositoryProvider).verifyOldPhone(code);
      if (!mounted) return;
      setState(() {
        _stepUpToken = stepUp.stepUpToken;
        _step = 2;
      });
      _toast('账号验证通过');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('验证失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendNewCode() async {
    final newEmail = _newEmailCtrl.text.trim();
    if (!AuthValidators.isEmail(newEmail) || AuthValidators.registrationIdentifier(newEmail) != null) {
      _toast('请输入有效的邮箱地址');
      return;
    }
    if (_newCooldown > 0 || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(userCenterRepositoryProvider).sendNewEmailCode(newEmail);
      if (!mounted) return;
      setState(() {
        _newCooldown = 60;
        _step = 3;
      });
      _startCooldown(oldPhone: false);
      _toast('验证码已发送');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('发送失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final token = _stepUpToken;
    if (token == null) {
      _toast('请先完成账号验证');
      setState(() => _step = 1);
      return;
    }
    final newEmail = _newEmailCtrl.text.trim();
    final code = _newCodeCtrl.text.trim();
    if (code.isEmpty) {
      _toast('请输入新邮箱收到的验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(userCenterRepositoryProvider).confirmEmailChange(
            newEmail: newEmail,
            code: code,
            stepUpToken: token,
          );
      if (!mounted) return;
      // 换绑成功后后端吊销全部会话：本地凭证失效，回登录页用新号重新登录。
      await ref.read(authControllerProvider.notifier).forceLocalSignOut();
      if (!mounted) return;
      _stepUpToken = null;
      context.go(RoutePath.login);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邮箱已更新，请重新登录')),
      );
    } on ApiException catch (e) {
      _stepUpToken = null;
      if (mounted) setState(() => _step = 1);
      _toast('${e.message}，请重新验证当前账号');
    } catch (_) {
      _stepUpToken = null;
      if (mounted) setState(() => _step = 1);
      _toast('绑定失败，请重新验证当前账号');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailMasked = ref.watch(userProfileProvider).valueOrNull?.emailMasked;

    return UserCenterScaffold(
      title: emailMasked == null ? '绑定邮箱' : '更换邮箱',
      actions: null,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (_step == 1)
            UserStepCard(
              index: 1,
              title: '验证当前账号',
              subtitle: '验证码将发送至已绑定邮箱或手机号',
              active: _step == 1,
              done: _step > 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _oldCodeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '验证码'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed:
                            (_oldCooldown > 0 || _busy) ? null : _sendOldCode,
                        child: Text(
                            _oldCooldown > 0 ? '${_oldCooldown}s' : '获取验证码'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _busy ? null : _verifyOldCode,
                    child: const Text('下一步'),
                  ),
                ],
              ),
            ),
          if (_step == 2)
            UserStepCard(
              index: 2,
              title: '填写新邮箱',
              subtitle: '新邮箱需未被平台其它账号使用',
              active: _step == 2,
              done: _step > 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _newEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '新邮箱'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _busy ? null : _sendNewCode,
                    child: const Text('下一步'),
                  ),
                ],
              ),
            ),
          if (_step == 3)
            UserStepCard(
              index: 3,
              title: '确认绑定',
              subtitle: '确认后需使用新邮箱重新登录',
              active: _step == 3,
              done: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newCodeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '新邮箱验证码'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed:
                            (_newCooldown > 0 || _busy) ? null : _sendNewCode,
                        child: Text(
                            _newCooldown > 0 ? '${_newCooldown}s' : '重新发送'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _busy ? null : _confirm,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('确认绑定'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
