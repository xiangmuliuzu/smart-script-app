import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../core/widgets/app_toast.dart';
import '../auth_feedback.dart';
import '../auth_navigation.dart';
import '../widgets/agreement_checkbox.dart';
import '../widgets/auth_buttons.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_page_scaffold.dart';
import '../widgets/phone_input.dart';
import '../widgets/underlined_input.dart';
import '../widgets/verify_code_input.dart';

/// 注册页：手机号 -> 验证码 -> 设置密码 -> 确认密码 -> 注册并登录。
///
/// 注册成功后服务端直接下发会话，登录守卫随即把根路由切到首页（不额外回跳）。
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _agreed = false;
  bool _obscure = true;
  bool _submitting = false;
  int _shakeSignal = 0;
  String? _phoneError;
  String? _codeError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _codeFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  /// 获取验证码：先本地校验手机号，再请求既有 `/auth/sms/send`（scene=REGISTER）。
  Future<bool> _handleRequestCode() async {
    FocusScope.of(context).unfocus();
    final phoneError = AuthValidators.phone(_phoneController.text);
    if (phoneError != null) {
      setState(() => _phoneError = phoneError);
      return false;
    }
    setState(() => _phoneError = null);

    try {
      await ref.read(authRepositoryProvider).sendSms(
            phone: _phoneController.text.trim(),
            scene: 'REGISTER',
          );
      if (!mounted) {
        return true;
      }
      showAppToast(context, '验证码已发送，请注意查收短信');
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        showAppToast(context, AuthFeedback.smsSendError(e));
      }
      return false;
    } catch (_) {
      if (mounted) {
        showAppToast(context, '验证码发送失败，请稍后重试');
      }
      return false;
    }
  }

  /// 注册：未勾选协议时只做提示与抖动，绝不提交接口。
  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();
    if (!_agreed) {
      setState(() => _shakeSignal += 1);
      showAppToast(context, '请先阅读并同意用户协议和隐私政策');
      return;
    }
    final phoneError = AuthValidators.phone(_phoneController.text);
    final codeError = AuthValidators.smsCode(_codeController.text);
    final passwordError = AuthValidators.password(_passwordController.text);
    final confirmError = AuthValidators.confirmPassword(
      _confirmController.text,
      _passwordController.text,
    );
    setState(() {
      _phoneError = phoneError;
      _codeError = codeError;
      _passwordError = passwordError;
      _confirmError = confirmError;
    });
    if (phoneError != null ||
        codeError != null ||
        passwordError != null ||
        confirmError != null) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            phone: _phoneController.text.trim(),
            code: _codeController.text.trim(),
            password: _passwordController.text,
          );
      // 注册成功后服务端直接下发令牌，登录守卫把根路由切到首页
    } on ApiException catch (e) {
      if (mounted) {
        showAppToast(context, e.message);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, '注册失败，请稍后重试');
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
            title: '注册新账号',
            subtitle: '验证手机号后设置登录密码',
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
            onSubmitted: (_) => _codeFocusNode.requestFocus(),
          ),
          const SizedBox(height: 8),
          VerifyCodeInput(
            controller: _codeController,
            focusNode: _codeFocusNode,
            errorText: _codeError,
            onRequestCode: _handleRequestCode,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocusNode.requestFocus(),
          ),
          const SizedBox(height: 8),
          UnderlinedInput(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            hintText: '8-64 位，含字母和数字',
            label: '密码',
            errorText: _passwordError,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
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
          const SizedBox(height: 8),
          UnderlinedInput(
            controller: _confirmController,
            hintText: '请再次输入密码',
            label: '确认',
            errorText: _confirmError,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleRegister(),
          ),
          const SizedBox(height: 20),
          AgreementCheckbox(
            value: _agreed,
            shakeSignal: _shakeSignal,
            onChanged: (value) => setState(() => _agreed = value),
            onUserAgreementTap: () => context.push(RoutePath.agreement),
            onPrivacyPolicyTap: () => context.push(RoutePath.privacyPolicy),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: '注册并登录',
            loading: _submitting,
            onPressed: _handleRegister,
          ),
        ],
      ),
    );
  }
}
