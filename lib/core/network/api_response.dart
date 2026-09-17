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
    final raw = json['data'];
    return ApiResponse<T>(
      code: (json['code'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
      data: raw == null ? null : (parser != null ? parser(raw) : raw as T),
    );
  }
}
