import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/network/interceptors/auth_interceptor.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/models/user.dart';

class _ScriptAdapter implements HttpClientAdapter {
  _ScriptAdapter(this.handler);

  final Response<dynamic> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final resp = handler(options);
    final bytes = utf8.encode(jsonEncode(resp.data));
    return ResponseBody.fromBytes(
      bytes,
      resp.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _CountingRepo implements AuthRepository {
  _CountingRepo(this.nextSession);

  final AuthSession nextSession;
  int refreshCalls = 0;

  @override
  Future<AuthSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? deviceName,
  }) async {
    refreshCalls++;
    return nextSession;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingRefreshRepo implements AuthRepository {
  @override
  Future<AuthSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? deviceName,
  }) async {
    throw Exception('replay');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthSession _session() => const AuthSession(
      accessToken: 'NEW_AT',
      refreshToken: 'NEW_RT',
      tokenType: 'Bearer',
      expiresIn: 1800,
      refreshExpiresIn: 86400,
      user: User(userId: 1, userType: UserType.user, nickname: 'u'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AuthInterceptor.debugRetryAdapter = null;
  });

  test('APP-04 Bearer 仅注入私有 App 请求', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    final storage = TokenStorage(secure, prefs);
    await storage.saveSession(accessToken: 'AT', refreshToken: 'RT');

    final dio = Dio(BaseOptions(
      baseUrl: 'http://t/api/v1',
      validateStatus: (s) => s != null && s < 500 && s != 401,
    ));
    AuthRepository? repo;
    final interceptor = AuthInterceptor(storage, () => repo!);
    dio.interceptors.add(interceptor);
    late RequestOptions seenPrivate;
    late RequestOptions seenPublic;
    final adapter = _ScriptAdapter((options) {
      if (options.path.contains('me')) seenPrivate = options;
      if (options.path.contains('password/login')) seenPublic = options;
      return Response(
        requestOptions: options,
        statusCode: 200,
        data: {'code': 200, 'message': 'ok', 'data': {}},
      );
    });
    dio.httpClientAdapter = adapter;
    AuthInterceptor.debugRetryAdapter = adapter;
    repo = _CountingRepo(_session());

    await dio.get('/auth/me');
    await dio.post('/auth/password/login', data: {'phone': '1', 'password': 'x'});

    expect(seenPrivate.headers['Authorization'], 'Bearer AT');
    expect(seenPublic.headers.containsKey('Authorization'), isFalse);
  });

  test('APP-05/06 并发 401 只刷新一次并各重试一次', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    final storage = TokenStorage(secure, prefs);
    await storage.saveSession(accessToken: 'OLD', refreshToken: 'RT');

    final dio = Dio(BaseOptions(
      baseUrl: 'http://t/api/v1',
      validateStatus: (s) => s != null && s < 500 && s != 401,
    ));
    late _CountingRepo repo;
    final interceptor = AuthInterceptor(storage, () => repo);
    dio.interceptors.add(interceptor);
    final adapter = _ScriptAdapter((options) {
      if (options.path == '/auth/token/refresh') {
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'code': 200,
            'message': 'ok',
            'data': {
              'accessToken': 'NEW_AT',
              'refreshToken': 'NEW_RT',
              'tokenType': 'Bearer',
              'expiresIn': 1800,
              'refreshExpiresIn': 86400,
              'user': {'userId': 1, 'userType': '01', 'nickname': 'u'},
            },
          },
        );
      }
      if (options.headers['Authorization'] == 'Bearer OLD') {
        return Response(
          requestOptions: options,
          statusCode: 401,
          data: {'code': 40101, 'message': 'access token expired', 'data': null},
        );
      }
      return Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'code': 200,
          'message': 'ok',
          'data': {'userId': 1, 'userType': '01', 'nickname': 'u'},
        },
      );
    });
    dio.httpClientAdapter = adapter;
    AuthInterceptor.debugRetryAdapter = adapter;
    repo = _CountingRepo(_session());

    await Future.wait([
      dio.get('/auth/me'),
      dio.get('/auth/me'),
    ]);

    expect(repo.refreshCalls, 1);
    expect(interceptor.refreshCountForTest, 1);
    expect(storage.token, 'NEW_AT');
  });

  test('APP-07 刷新失败/重放清凭据', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    final storage = TokenStorage(secure, prefs);
    await storage.saveSession(accessToken: 'OLD', refreshToken: 'RT');

    final dio = Dio(BaseOptions(baseUrl: 'http://t/api/v1'));
    final repo = _FailingRefreshRepo();
    final interceptor = AuthInterceptor(storage, () => repo);
    dio.interceptors.add(interceptor);
    dio.httpClientAdapter = _ScriptAdapter((options) {
      return Response(
        requestOptions: options,
        statusCode: 401,
        data: {'code': 40103, 'message': 'refresh token replay', 'data': null},
      );
    });

    await expectLater(
      dio.get('/auth/me'),
      throwsA(isA<DioException>()),
    );
    expect(storage.token, isNull);
    expect(storage.refreshToken, isNull);
  });

  test('APP-08 再次 401 不循环刷新', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    final storage = TokenStorage(secure, prefs);
    await storage.saveSession(accessToken: 'OLD', refreshToken: 'RT');

    final dio = Dio(BaseOptions(baseUrl: 'http://t/api/v1'));
    late _CountingRepo repo;
    final interceptor = AuthInterceptor(storage, () => repo);
    dio.interceptors.add(interceptor);
    dio.httpClientAdapter = _ScriptAdapter((options) {
      return Response(
        requestOptions: options,
        statusCode: 401,
        data: {'code': 40101, 'message': 'expired', 'data': null},
      );
    });
    repo = _CountingRepo(_session());

    await expectLater(dio.get('/auth/me'), throwsA(isA<DioException>()));
    expect(repo.refreshCalls, 1);
    expect(storage.token, isNull);
  });
}
