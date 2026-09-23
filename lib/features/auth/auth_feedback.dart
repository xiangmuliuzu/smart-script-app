import '../../core/network/api_exception.dart';

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
      return '发送过于频繁，请 $retryAfterSeconds 秒后重试';
    }
    return e.message;
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
