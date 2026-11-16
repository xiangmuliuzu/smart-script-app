import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/friendly_error.dart';
import '../../core/network/session_events.dart';

/// 认证页的用户可见文案（统一收口，避免同一错误在不同页面提示不一致）。
class AuthFeedback {
  AuthFeedback._();

  /// 发送验证码失败的提示文案。
  ///
  /// 频控失败时后端返回 `data.retryAfterSeconds`（如 `{"code":42901,
  /// "message":"sms cooldown","data":{"retryAfterSeconds":60}}`），
  /// 据此给出可读提示。**失败一律不倒计时**：由用户自行决定何时重试，
  /// 避免「发送没成功却被锁 60 秒」。
  static String smsSendError(ApiException e) {
    final retryAfterSeconds = _retryAfterSeconds(e.data);
    if (retryAfterSeconds != null) {
      return '操作过于频繁，请 $retryAfterSeconds 秒后重试';
    }
    return FriendlyError.message(e);
  }

  /// 页面层可读文案：统一收敛为中文，优先保留后端安全中文。
  static String apiMessage(ApiException e) {
    return FriendlyError.message(e);
  }

  static String passwordLoginError(ApiException e) {
    if (e.code == AppAuthErrorCodes.invalidRequest) {
      return '手机号或密码错误，请重试';
    }
    return apiMessage(e);
  }

  /// 账号被禁用（40301）的提示文案。
  ///
  /// 该状态重新登录也无法恢复，因此文案直接指引联系客服/管理员。
  static const String accountDisabledHint = FriendlyError.accountDisabled;

  /// 会话失效的全局提示文案；返回 null 表示该原因不弹提示。
  ///
  /// 仅账号禁用弹提示：普通 Token 过期已由「踢回登录页」表达，
  /// 不加额外提示以免与既有 401 交互不一致（如需统一提示需产品确认）。
  static String? sessionExpiryPrompt(SessionExpiryReason reason) {
    switch (reason) {
      case SessionExpiryReason.accountDisabled:
        return accountDisabledHint;
      case SessionExpiryReason.tokenExpired:
        return null;
    }
  }

  static int? _retryAfterSeconds(dynamic data) {
    if (data is Map) {
      final retry = data['retryAfterSeconds'];
      if (retry is num && retry > 0) {
        return retry.toInt();
      }
    }
    return null;
  }
}
