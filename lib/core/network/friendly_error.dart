import 'api_exception.dart';

/// 用户可见错误文案的统一收敛。
///
/// 优先级：后端安全中文 > 错误码文案 > HTTP/网络兜底 > 通用兜底。
/// 任何英文、HTTP 状态码、异常类名、堆栈信息都不会直接展示给用户。
class FriendlyError {
  FriendlyError._();

  static const String generic = '操作未完成，请稍后再试';
  static const String param = '您的信息不符合规范，请检查后重试';
  static const String loginExpired = '登录状态已过期，请重新登录';
  static const String forbidden = '暂无权限执行此操作';
  static const String notFound = '内容不存在或暂时不可用';
  static const String serverBusy = '服务暂时不可用，请稍后再试';
  static const String network = '网络连接异常，请检查网络后重试';
  static const String timeout = '请求超时，请稍后再试';
  static const String fileTooLarge = '文件过大，请更换后重试';
  static const String tooFrequent = '操作过于频繁，请稍后再试';
  static const String accountDisabled = '账号暂时无法使用，请联系客服或管理员';

  static String message(Object error, {int? status, int? code}) {
    if (error is ApiException) {
      final backend = sanitizeOrNull(error.message);
      if (backend != null) return backend;
      final byCode = messageForCode(code ?? error.code);
      if (byCode != null) return byCode;
      final byStatus = messageForStatus(status ?? error.code);
      if (byStatus != null) return byStatus;
      return generic;
    }
    final text = sanitizeOrNull(error.toString());
    if (text != null) return text;
    return messageForStatus(status) ?? generic;
  }

  static String? messageForCode(int? code) {
    switch (code) {
      case 40000:
        return param;
      case 40001:
        return '验证码错误，请重新输入';
      case 40002:
        return '验证码已过期，请重新获取';
      case 40901:
        return '验证码已使用，请重新获取';
      case 40902:
        return '该手机号或邮箱已注册，请直接登录';
      case 40903:
        return '协议已更新，请重新阅读并同意';
      case 40905:
        return '实名认证正在审核或已通过，请勿重复提交';
      case 40906:
        return '请勿重复提交';
      case 40907:
        return '该昵称已被使用，请更换后重试';
      case 40908:
        return '创作者申请正在审核或已通过，请勿重复提交';
      case 40100:
      case 40101:
      case 40102:
        return loginExpired;
      case 40300:
        return forbidden;
      case 40301:
        return accountDisabled;
      case 40400:
        return notFound;
      case 41300:
        return fileTooLarge;
      case 42901:
      case 42902:
        return tooFrequent;
      case 50000:
        return serverBusy;
      default:
        return null;
    }
  }

  static String? messageForStatus(int? status) {
    switch (status) {
      case 400:
        return param;
      case 401:
        return loginExpired;
      case 403:
        return forbidden;
      case 404:
        return notFound;
      case 405:
        return '请求方式不正确，请稍后再试';
      case 413:
        return fileTooLarge;
      case 429:
        return tooFrequent;
      case 500:
      case 502:
      case 503:
        return serverBusy;
      case 408:
      case 504:
        return timeout;
      default:
        return null;
    }
  }

  /// 后端文案只有在“含中文且不含技术特征”时才可直接展示。
  static String? sanitizeOrNull(String? message) {
    if (message == null) return null;
    final text = message.trim();
    if (text.isEmpty) return null;
    if (!RegExp(r'[一-鿿]').hasMatch(text)) return null;
    final lower = text.toLowerCase();
    const markers = ['http', 'exception', 'traceback', 'stacktrace', 'sqlexception',
      'null', 'undefined', 'com.ruoyi', 'com.smartscript', 'java.'];
    if (markers.any(lower.contains) || text.contains('/') || text.contains('\\')) {
      return null;
    }
    return text;
  }

  static String sanitize(String? message, {String fallback = generic}) =>
      sanitizeOrNull(message) ?? fallback;
}
