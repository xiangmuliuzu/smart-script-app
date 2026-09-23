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
import '../widgets/social_login_area.dart';
import '../widgets/verify_code_input.dart';

/// 登录首页（主流程：手机号 + 验证码）。
///
/// 信息架构参考同类 App 登录页：返回 -> Logo -> 主标题 -> 手机号 -> 验证码 ->
/// 协议勾选 -> 主按钮 -> 次按钮（账号密码登录）-> 注册入口 -> 第三方登录。
///
/// 登录成功后消费一次守卫保存的回跳意图（规格 §8.1），保持既有登录回跳行为。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();

  bool _agreed = false;
  bool _submitting = false;
  int _shakeSignal = 0;
  String? _phoneError;
  String? _codeError;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  /// 获取验证码：先本地校验手机号，再请求既有 `/auth/sms/send`（scene=LOGIN）。
  /// 返回是否发送成功，失败时按钮立即恢复可点（不倒计时）。
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
            scene: 'LOGIN',
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

  /// 登录：未勾选协议时只做提示与抖动，绝不提交接口。
  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_agreed) {
      setState(() => _shakeSignal += 1);
      showAppToast(context, '请先阅读并同意用户协议和隐私政策');
      return;
    }
    final phoneError = AuthValidators.phone(_phoneController.text);
    final codeError = AuthValidators.smsCode(_codeController.text);
    setState(() {
      _phoneError = phoneError;
      _codeError = codeError;
    });
    if (phoneError != null || codeError != null) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).loginWithSms(
            phone: _phoneController.text.trim(),
            code: _codeController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      // 登录成功后消费一次回跳意图，否则回安全默认首页
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

  /// 微信 / QQ 入口：后端 OAuth 当前固定返回「暂未开放」，只提示，不做假登录。
  void _handleSocialLogin(String providerName) {
    showAppToast(context, '$providerName登录暂未开放，敬请期待');
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      bottom: SocialLoginArea(
        onWechatTap: () => _handleSocialLogin('微信'),
        onQqTap: () => _handleSocialLogin('QQ'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeader(
            title: '登录后体验完整功能',
            onBack: () => leaveAuthHome(context),
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
            onSubmitted: (_) => _handleLogin(),
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
            label: '登录',
            loading: _submitting,
            onPressed: _handleLogin,
          ),
          const SizedBox(height: 14),
          SecondaryButton(
            label: '账号密码登录',
            onPressed: () => context.go(RoutePath.passwordLogin),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '未拥有账号？',
                style: TextStyle(fontSize: 13, color: AppColors.text3),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.go(RoutePath.register),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(
                    '点击注册',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
