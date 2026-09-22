import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_widgets.dart';

/// 换绑手机号（规格 §8.5，契约 §1.4）。
///
/// 三步流程，两步凭证：
///   1. 向**当前登录用户自己的旧手机号**发码并验证 -> 取得一次性 stepUpToken
///   2. 向新手机号发码（服务端先校验新号未被占用）
///   3. 确认换绑 -> 后端吊销全部会话，界面要求用新手机号重新登录
///
/// 关键约束：
///   - 页面**不展示也不要求输入**完整旧手机号：旧号由服务端按当前身份取，
///     验证码经专用端点发到该号（见 /users/me/phone/change/old/send）；
///   - stepUpToken 只保存在内存中，不落盘、不打印；
///   - 换绑成功属于「强制退出」路径，不生成回跳意图（规格 §8.1 末条）。
class PhoneChangePage extends ConsumerStatefulWidget {
  const PhoneChangePage({super.key});

  @override
  ConsumerState<PhoneChangePage> createState() => _PhoneChangePageState();
}

class _PhoneChangePageState extends ConsumerState<PhoneChangePage> {
  final _oldCodeCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
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
    _newPhoneCtrl.dispose();
    _newCodeCtrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      _toast('验证码已发送至当前手机号');
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
      _toast('请输入当前手机号收到的验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final stepUp = await ref.read(userCenterRepositoryProvider).verifyOldPhone(code);
      if (!mounted) return;
      setState(() {
        _stepUpToken = stepUp.stepUpToken;
        _step = 2;
      });
      _toast('当前手机号验证通过');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('验证失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendNewCode() async {
    final newPhone = _newPhoneCtrl.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(newPhone)) {
      _toast('请输入正确的 11 位手机号');
      return;
    }
    if (_newCooldown > 0 || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(userCenterRepositoryProvider).sendNewPhoneCode(newPhone);
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
      _toast('请先完成当前手机号验证');
      setState(() => _step = 1);
      return;
    }
    final newPhone = _newPhoneCtrl.text.trim();
    final code = _newCodeCtrl.text.trim();
    if (code.isEmpty) {
      _toast('请输入新手机号收到的验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(userCenterRepositoryProvider).confirmPhoneChange(
            newPhone: newPhone,
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
        const SnackBar(content: Text('手机号已更换，请使用新手机号重新登录')),
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('换绑失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phoneMasked = ref.watch(authControllerProvider).user?.phoneMasked;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('更换手机号')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          UserStepCard(
            index: 1,
            title: '验证当前手机号',
            subtitle: phoneMasked ?? '当前手机号未获取',
            active: _step == 1,
            done: _step > 1,
            child: Column(
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
                      onPressed: (_oldCooldown > 0 || _busy) ? null : _sendOldCode,
                      child: Text(_oldCooldown > 0 ? '${_oldCooldown}s' : '获取验证码'),
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
          const SizedBox(height: 12),
          UserStepCard(
            index: 2,
            title: '填写新手机号',
            subtitle: '新手机号需未被平台其它账号使用',
            active: _step == 2,
            done: _step > 2,
            child: Column(
              children: [
                TextField(
                  controller: _newPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '新手机号'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _busy ? null : _sendNewCode,
                  child: const Text('发送验证码'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          UserStepCard(
            index: 3,
            title: '确认换绑',
            subtitle: '确认后需使用新手机号重新登录',
            active: _step == 3,
            done: false,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newCodeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '新号验证码'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: (_newCooldown > 0 || _busy) ? null : _sendNewCode,
                      child: Text(_newCooldown > 0 ? '${_newCooldown}s' : '重新发送'),
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
                      : const Text('确认换绑'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
