// 测试支撑：可编排的 Dio 适配器 + 标准信封构造器。
//
// 目的：让 widget/单元测试通过**真实**的 ApiClient/Repository 代码路径发起请求，
// 只把 HTTP 传输层替换掉，从而覆盖「业务码 → ApiException」「401 → 会话失效」等真实映射，
// 而不是用假的 Repository 绕过被测逻辑。
//
// 用法：
//   final api = ScriptedApi();
//   api.reply('/messages', Envelope.ok({'total': 0, 'list': []}));
//   ... ProviderScope(overrides: [api.override, ...])
//   expect(api.countOf('/messages'), 1);
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/providers/app_providers.dart';

/// 后端统一信封：`{code, message, data}`。
class Envelope {
  const Envelope(this.status, this.body);

  final int status;
  final Object? body;

  /// 业务成功。
  static Envelope ok(Object? data) =>
      Envelope(200, {'code': 200, 'message': 'ok', 'data': data});

  /// 业务失败：HTTP 200 + 业务码（RuoYi 风格，如 40400 资源不存在）。
  static Envelope fail(int code, String message) =>
      Envelope(200, {'code': code, 'message': message, 'data': null});

  /// HTTP 层失败（如 403 无权限、500 服务端错误）。
  static Envelope http(int status, String message) =>
      Envelope(status, {'code': status, 'message': message, 'data': null});

  /// 非信封结构（用于验证「响应格式错误」分支）。
  static Envelope raw(int status, Object? body) => Envelope(status, body);
}

typedef ScriptedHandler = Envelope Function(RequestOptions options);

/// 可编排的假后端：按「路径包含」匹配并返回预设响应，同时记录全部请求。
class ScriptedApi {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, ScriptedHandler> _routes = <String, ScriptedHandler>{};

  /// 非空时所有响应都会挂起，直到 [release] 被调用（用于断言加载态）。
  Completer<void>? _gate;

  void gate() => _gate = Completer<void>();

  void release() {
    final g = _gate;
    _gate = null;
    if (g != null && !g.isCompleted) g.complete();
  }

  /// 注册固定响应。
  void reply(String pathContains, Envelope response) {
    _routes[pathContains] = (_) => response;
  }

  /// 注册动态响应（可按请求参数或调用次数变化）。
  void handle(String pathContains, ScriptedHandler handler) {
    _routes[pathContains] = handler;
  }

  /// 命中次数（用于断言「重试确实重新发起请求」）。
  int countOf(String pathContains) =>
      requests.where((r) => r.path.contains(pathContains)).length;

  /// 全部已记录请求的路径与查询串。
  List<String> get paths => requests.map((r) => r.path).toList();

  Dio buildDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://scripted.test/api/v1',
        // 与 ApiClient.buildDio 保持一致：401 交给上层处理，其余 <500 视为可读响应
        validateStatus: (status) => status != null && status < 500 && status != 401,
      ),
    );
    dio.httpClientAdapter = _ScriptedAdapter(this);
    return dio;
  }

  /// 直接替换 ApiClient（Repository 依赖 apiClientProvider）。
  Override get override => apiClientProvider.overrideWithValue(ApiClient(buildDio()));
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.api);

  final ScriptedApi api;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    api.requests.add(options);
    final gate = api._gate;
    if (gate != null) await gate.future;

    // 最长匹配优先：`/messages/unread-count` 必须优先于 `/messages`
    final matches = api._routes.keys.where((k) => options.path.contains(k)).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (matches.isNotEmpty) {
      final env = api._routes[matches.first]!(options);
      return ResponseBody.fromBytes(
        utf8.encode(jsonEncode(env.body)),
        env.status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    // 未编排的路径：明确失败，避免测试因「没配路由」而误判为通过
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'code': 500, 'message': 'no scripted route for ${options.path}', 'data': null})),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
