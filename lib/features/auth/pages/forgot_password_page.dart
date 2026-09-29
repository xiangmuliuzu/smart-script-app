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
import '../widgets/auth_buttons.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_page_scaffold.dart';
import '../widgets/phone_input.dart';
import '../widgets/underlined_input.dart';
import '../widgets/verify_code_input.dart';

/// A3 密码重置：成功后清会话并要求重新登录（APP-12）。
///
/// 与登录 / 注册页共用同一套输入行 / 按钮组件，保证背景、间距、字号与错误态完全一致。
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _pwdFocusNode = FocusNode();

  bool _loading = false;
  bool _obscure = true;
  String? _phoneError;
  String? _codeError;
  String? _pwdError;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _pwdCtrl.dispose();
    _pwdFocusNode.dispose();
    super.dispose();
  }

  /// 发送验证码：先本地校验手机号，成功返回 true 交给 VerifyCodeInput 倒计时，
  /// 失败时按钮立即恢复可点（不倒计时），与登录页行为一致。
  Future<bool> _sendSms() async {
    final phoneError = AuthValidators.phone(_phoneCtrl.text);
    if (phoneError != null) {
      setState(() => _phoneError = phoneError);
      return false;
    }
    setState(() => _phoneError = null);

    try {
      await ref
          .read(authRepositoryProvider)
          .sendSms(phone: _phoneCtrl.text.trim(), scene: 'RESET_PASSWORD');
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final phoneError = AuthValidators.phone(_phoneCtrl.text);
    final codeError = AuthValidators.smsCode(_codeCtrl.text);
    final pwdError = AuthValidators.password(_pwdCtrl.text);
    setState(() {
      _phoneError = phoneError;
      _codeError = codeError;
      _pwdError = pwdError;
    });
    if (phoneError != null || codeError != null || pwdError != null) {
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
            phone: _phoneCtrl.text.trim(),
            code: _codeCtrl.text.trim(),
            newPassword: _pwdCtrl.text,
          );
      if (!mounted) {
        return;
      }
      showAppToast(context, '密码已重置，请重新登录');
      context.go(RoutePath.login);
    } on ApiException catch (e) {
      if (mounted) {
        showAppToast(context, AuthFeedback.apiMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
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
            title: '重置密码',
            onBack: () => context.go(RoutePath.login),
          ),
          PhoneInput(
            controller: _phoneCtrl,
            errorText: _phoneError,
            onChanged: (_) {
              if (_phoneError != null) {
                setState(() => _phoneError = null);
              }
            },
            onSubmitted: (_) => _pwdFocusNode.requestFocus(),
          ),
          const SizedBox(height: 8),
          VerifyCodeInput(
            controller: _codeCtrl,
            errorText: _codeError,
            onRequestCode: _sendSms,
            onSubmitted: (_) => _pwdFocusNode.requestFocus(),
          ),
          const SizedBox(height: 8),
          UnderlinedInput(
            controller: _pwdCtrl,
            focusNode: _pwdFocusNode,
            hintText: '8-64位，含字母与数字',
            label: '新密码',
            errorText: _pwdError,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            trailing: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: AppColors.text3,
              ),
              tooltip: _obscure ? '显示密码' : '隐藏密码',
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: '重置密码',
            loading: _loading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
