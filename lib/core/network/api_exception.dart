/// 统一的业务/网络异常。
///
/// 页面层只需 `catch (e on ApiException)` 并用 `e.message` 提示用户，
/// 不必关心是 Dio 网络错误还是后端返回的 code != 200。
class ApiException implements Exception {
  ApiException(this.message, {this.code, this.data});

  /// 面向用户的可读消息。
  final String message;

  /// 业务错误码（后端 `code`）；网络层错误时为 null。
  final int? code;

  /// 附带数据（如校验失败的字段信息），可为空。
  final dynamic data;

  @override
  String toString() => 'ApiException(code: $code, message: $message)';
}
