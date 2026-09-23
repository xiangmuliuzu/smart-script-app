import '../config/app_config.dart';

/// 认证表单校验：**与当前后端契约一致**（后端仍会二次校验，前端只为即时反馈）。
///
/// 对应 DTO 约束：
///   * `SmsSendRequest.phone` / `SmsLoginRequest.phone` / `RegisterRequest.phone`
///     / `PasswordLoginRequest.phone` -> `^1\d{10}$`
///   * `SmsLoginRequest.code` / `RegisterRequest.code` -> `@Size(min = 4, max = 8)`
///   * `RegisterRequest.password` / `PasswordLoginRequest.password` -> 8-64 位，
///     且服务端 [validatePasswordPolicy] 要求同时包含字母与数字。
class AuthValidators {
  AuthValidators._();

  static final RegExp _phonePattern = RegExp(r'^1\d{10}$');
  static final RegExp _smsCodePattern = RegExp(r'^\d{4,8}$');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');
  static final RegExp _hasDigit = RegExp(r'\d');

  /// 手机号：中国大陆 11 位，必须以 1 开头。
  static String? phone(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return '请输入手机号';
    }
    if (text.length != AppConfig.phoneLength || !_phonePattern.hasMatch(text)) {
      return '请输入正确的 11 位手机号';
    }
    return null;
  }

  /// 验证码：4-8 位数字。
  static String? smsCode(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return '请输入验证码';
    }
    if (!_smsCodePattern.hasMatch(text)) {
      return '请输入 ${AppConfig.smsCodeMinLength}-${AppConfig.smsCodeMaxLength} 位数字验证码';
    }
    return null;
  }

  /// 密码：8-64 位，且同时包含字母与数字。
  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) {
      return '请输入密码';
    }
    if (text.length < AppConfig.passwordMinLength ||
        text.length > AppConfig.passwordMaxLength) {
      return '密码长度需为 ${AppConfig.passwordMinLength}-${AppConfig.passwordMaxLength} 位';
    }
    if (!_hasLetter.hasMatch(text) || !_hasDigit.hasMatch(text)) {
      return '密码需同时包含字母和数字';
    }
    return null;
  }

  /// 登录密码：不校验强度（老账号可能是历史规则下设置的），仅要求非空。
  static String? loginPassword(String? value) {
    if ((value ?? '').isEmpty) {
      return '请输入密码';
    }
    return null;
  }

  /// 确认密码一致性。
  static String? confirmPassword(String? value, String original) {
    final text = value ?? '';
    if (text.isEmpty) {
      return '请再次输入密码';
    }
    if (text != original) {
      return '两次输入的密码不一致';
    }
    return null;
  }
}
