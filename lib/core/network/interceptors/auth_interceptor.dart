import 'dart:async';

import 'package:dio/dio.dart';

import '../../../features/auth/data/auth_repository.dart';
import '../../storage/token_storage.dart';

/// A3 AuthInterceptor:
/// - Bearer inject only for non-public App API requests
/// - single-flight refresh + waiter queue
/// - at most one retry after successful refresh
/// - non-retryable classification clears credentials once
class AuthInterceptor extends Interceptor {
  AuthInterceptor(
    this._storage,
    this._repositoryResolver, [
    this._refreshCountProbe,
  ]);

  final TokenStorage _storage;
  final AuthRepository Function() _repositoryResolver;
  final int Function()? _refreshCountProbe;

  static const List<String> _publicPaths = [
    '/auth/sms/send',
    '/auth/sms/login',
    '/auth/password/login',
    '/auth/register',
    '/auth/token/refresh',
    '/auth/password/reset',
    '/auth/agreements',
  ];

  static const String _retryHeader = 'X-Auth-Retry';
  static const String _deviceId = 'flutter-device';

  /// Test seam: when set, retry requests use this adapter (unit tests only).
  static HttpClientAdapter? debugRetryAdapter;

  Completer<bool>? _refreshInFlight;
  int _refreshCount = 0;

  AuthRepository get _repo => _repositoryResolver();

  bool isPublic(String path) {
    final p = path.startsWith('/api/v1') ? path.substring('/api/v1'.length) : path;
    if (p.startsWith('/auth/oauth/')) return true;
    return _publicPaths.any((e) => p == e || p.startsWith(e));
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _storage.token;
    if (token != null && token.isNotEmpty && !isPublic(options.path)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final options = err.requestOptions;
    final alreadyRetried = options.headers[_retryHeader] == true;

    if (status != 401 || isPublic(options.path) || alreadyRetried) {
      handler.next(err);
      return;
    }

    final code = _businessCode(err);
    final hasRefresh = _storage.refreshToken != null && _storage.refreshToken!.isNotEmpty;
    // 40101 allows refresh; unknown 401 with refresh token also tries once.
    // 40100/40102/40103/40300/40301 must not refresh.
    final nonRetryable = code == 40100 ||
        code == 40102 ||
        code == 40103 ||
        code == 40300 ||
        code == 40301;
    final canRefresh = hasRefresh && !nonRetryable && (code == 40101 || code == null);
    if (!canRefresh) {
      await _storage.clear();
      handler.next(err);
      return;
    }

    final authHeader = options.headers['Authorization'];
    final oldToken = authHeader is String && authHeader.startsWith('Bearer ')
        ? authHeader.substring(7)
        : (_storage.token ?? '');
    final ok = await _singleFlightRefresh(oldToken: oldToken);
    if (!ok) {
      await _storage.clear();
      handler.next(err);
      return;
    }

    final token = _storage.token;
    if (token == null || token.isEmpty) {
      await _storage.clear();
      handler.next(err);
      return;
    }

    options.headers['Authorization'] = 'Bearer $token';
    options.headers[_retryHeader] = true;
    try {
      final retryDio = Dio(BaseOptions(
        baseUrl: options.baseUrl,
        contentType: Headers.jsonContentType,
        validateStatus: (s) => s != null && s < 500 && s != 401,
      ));
      final adapter = debugRetryAdapter;
      if (adapter != null) {
        retryDio.httpClientAdapter = adapter;
      }
      final resp = await retryDio.fetch<dynamic>(options);
      if (resp.statusCode != null && resp.statusCode! >= 400) {
        // Treat post-refresh error as non-retryable; clear once (APP-08).
        await _storage.clear();
        handler.next(err);
        return;
      }
      handler.resolve(resp);
    } catch (_) {
      // APP-08: second 401 after refresh must not loop.
      await _storage.clear();
      handler.next(err);
    }
  }

  /// APP-05: concurrent 401s share one refresh request.
  /// If a prior refresh already rotated the token, return success without a second call.
  Future<bool> _singleFlightRefresh({required String oldToken}) {
    final inflight = _refreshInFlight;
    if (inflight != null && !inflight.isCompleted) {
      return inflight.future;
    }
    final current = _storage.token;
    if (current != null && current.isNotEmpty && current != oldToken) {
      return Future<bool>.value(true);
    }
    final c = Completer<bool>();
    _refreshInFlight = c;
    _doRefresh().then((ok) {
      if (!c.isCompleted) c.complete(ok);
    }).catchError((Object _) {
      if (!c.isCompleted) c.complete(false);
    });
    return c.future;
  }

  Future<bool> _doRefresh() async {
    final refresh = _storage.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final session = await _repo.refresh(
        refreshToken: refresh,
        deviceId: _deviceId,
      );
      await _storage.updateTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      await _storage.cacheUser(session.user.toJson());
      _refreshCount++;
      return true;
    } catch (_) {
      return false;
    }
  }

  int get refreshCountForTest => _refreshCountProbe?.call() ?? _refreshCount;

  static int? _businessCode(DioException err) {
    final data = err.response?.data;
    if (data is Map && data['code'] is num) {
      return (data['code'] as num).toInt();
    }
    return null;
  }
}
