import '../constants/app_constants.dart';

/// 统一响应包（接口文档 1.2：`{ "code": 200, "message": "success", "data": {} }`）。
class ApiResponse<T> {
  const ApiResponse({required this.code, required this.message, this.data});

  final int code;
  final String message;
  final T? data;

  bool get isSuccess => code == AppConstants.codeSuccess;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json, {
    T Function(dynamic raw)? parser,
  }) {
    // RuoYi login/captcha responses carry their fields at the top level.
    final raw = json['data'] ??
        (json.containsKey('token') ||
                json.containsKey('captchaEnabled') ||
                json.containsKey('user')
            ? json
            : null);
    return ApiResponse<T>(
      code: (json['code'] as num?)?.toInt() ?? 0,
      message: json['msg'] as String? ?? json['message'] as String? ?? '',
      data: raw == null ? null : (parser != null ? parser(raw) : raw as T),
    );
  }
}
