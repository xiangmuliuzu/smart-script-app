import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../core/widgets/app_toast.dart';
import '../auth_navigation.dart';
import '../widgets/auth_buttons.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_page_scaffold.dart';
import '../widgets/phone_input.dart';
import '../widgets/underlined_input.dart';

/// 账号密码登录页（登录首页的次入口）。
///
/// 与登录首页共用同一套输入行 / 按钮组件，保证间距、字号与错误态完全一致。
class PasswordLoginPage extends ConsumerStatefulWidget {
  const PasswordLoginPage({super.key});

  @override
  ConsumerState<PasswordLoginPage> createState() => _PasswordLoginPageState();
}

class _PasswordLoginPageState extends ConsumerState<PasswordLoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _obscure = true;
  bool _submitting = false;
  String? _phoneError;
  String? _passwordError;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    final phoneError = AuthValidators.phone(_phoneController.text);
    final passwordError = AuthValidators.loginPassword(_passwordController.text);
    setState(() {
      _phoneError = phoneError;
      _passwordError = passwordError;
    });
    if (phoneError != null || passwordError != null) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).loginWithPassword(
            _phoneController.text.trim(),
            _passwordController.text,
          );
      if (!mounted) {
        return;
      }
      // 与验证码登录一致：登录成功后消费一次回跳意图
      resolvePostLoginTarget(context, ref);
    } on ApiException catch (e) {
      if (mounted) {
        showAppToast(context, e.message);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, '登录失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeader(
            title: '账号密码登录',
            subtitle: '使用手机号与登录密码进入平台',
            onBack: () => backToLogin(context),
          ),
          PhoneInput(
            controller: _phoneController,
            errorText: _phoneError,
            onChanged: (_) {
              if (_phoneError != null) {
                setState(() => _phoneError = null);
              }
            },
            onSubmitted: (_) => _passwordFocusNode.requestFocus(),
          ),
          const SizedBox(height: 8),
          UnderlinedInput(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            hintText: '请输入密码',
            label: '密码',
            errorText: _passwordError,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleLogin(),
            trailing: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
                color: AppColors.text3,
              ),
              tooltip: _obscure ? '显示密码' : '隐藏密码',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(RoutePath.forgotPassword),
              child: const Text('忘记密码？', style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: '登录',
            loading: _submitting,
            onPressed: _handleLogin,
          ),
          const SizedBox(height: 14),
          SecondaryButton(
            label: '验证码登录',
            onPressed: () => backToLogin(context),
          ),
        ],
      ),
    );
  }
}
