import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/interceptors/auth_interceptor.dart';
import 'package:script_app/core/network/session_events.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/core/constants/app_constants.dart';

class _GatedSecure extends InMemoryTokenSecureStorage {
  Completer<void>? writeGate;
  @override
  Future<void> write(String key, String value) async {
    if (key == AppConstants.kAccessToken && writeGate != null) {
      await writeGate!.future;
    }
    await super.write(key, value);
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body,
          Future<void>? cancelFuture) async =>
      respond(options);
}

ResponseBody _body(Map<String, dynamic> data, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TokenStorage storage;
  late InMemoryTokenSecureStorage secure;
  late Dio dio;
  late ApiClient api;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secure = InMemoryTokenSecureStorage();
    storage = TokenStorage(secure, await SharedPreferences.getInstance());
    await storage.saveSession(token: 'ruoyi-token');
    dio = ApiClient.buildDio(AuthInterceptor(storage));
    api = ApiClient(dio);
  });

  test('RuoYi token is injected into private requests only', () async {
    dio.httpClientAdapter = _Adapter((request) {
      if (request.path == '/users/me/profile') {
        expect(request.headers['Authorization'], 'Bearer ruoyi-token');
      } else {
        expect(request.headers.containsKey('Authorization'), isFalse);
      }
      return _body({'code': 200});
    });
    await api.get<void>('/users/me/profile');
    await api.post<void>('/auth/login');
    await api.post<void>('/auth/email/send');
    await api.get<void>('/auth/captchaImage');
    expect(await secure.read(AppConstants.kRefreshToken), isNull);
  });

  test('password login uses LoginBody and top-level token', () async {
    dio.httpClientAdapter = _Adapter((request) {
      expect(request.path, '/auth/login');
      expect(request.data, {
        'username': '13900000007',
        'password': 'Passw0rdX',
        'code': '1234',
        'uuid': 'captcha-id'
      });
      return _body({
        'code': 200,
        'msg': '操作成功',
        'token': 'new-token',
        'user': {'userId': 8, 'userType': '01', 'nickname': 'user'}
      });
    });
    final result = await AuthRepository(api).passwordLogin(
        phone: '13900000007',
        password: 'Passw0rdX',
        deviceId: 'device',
        code: '1234',
        uuid: 'captcha-id');
    expect(result.token, 'new-token');
    expect(result.user.userId, 8);
  });

  test('captcha consumes native RuoYi response', () async {
    dio.httpClientAdapter = _Adapter((request) {
      expect(request.uri.path, '/api/v1/auth/captchaImage');
      return _body({'code': 200, 'msg': '操作成功', 'captchaEnabled': false});
    });
    expect(await AuthRepository(api).captcha(),
        containsPair('captchaEnabled', false));
  });

  test('expired Redis session clears login with no refresh or retry', () async {
    int requests = 0;
    dio.httpClientAdapter = _Adapter((request) {
      requests++;
      return _body({'code': 40100, 'message': 'unauthorized'}, 401);
    });
    await expectLater(api.get<void>('/auth/me'), throwsA(anything));
    expect(requests, 1);
    expect(storage.token, isNull);
  });

  test('permission and transient server errors preserve login', () async {
    dio.httpClientAdapter =
        _Adapter((_) => _body({'code': 40300, 'message': 'forbidden'}, 403));
    await expectLater(
        api.get<void>('/content/works/drafts'), throwsA(anything));
    expect(storage.token, 'ruoyi-token');
    dio.httpClientAdapter =
        _Adapter((_) => _body({'code': 500, 'msg': 'error'}, 500));
    await expectLater(api.get<void>('/auth/me'), throwsA(anything));
    expect(storage.token, 'ruoyi-token');
  });

  test('stale 401 cannot expire a newer login', () async {
    final pending = Completer<ResponseBody>(), started = Completer<void>();
    int expired = 0;
    final sub =
        SessionEvents.instance.onSessionExpired.listen((_) => expired++);
    dio.httpClientAdapter = _Adapter((_) {
      started.complete();
      return pending.future;
    });
    final failed = expectLater(api.get<void>('/auth/me'), throwsA(anything));
    await started.future;
    await storage.saveSession(token: 'new-session');
    pending.complete(_body({'code': 40100}, 401));
    await failed;
    await Future<void>.delayed(Duration.zero);
    expect(storage.token, 'new-session');
    expect(expired, 0);
    await sub.cancel();
  });

  test('RuoYi msg reaches the form', () async {
    dio.httpClientAdapter =
        _Adapter((_) => _body({'code': 40000, 'msg': '验证码错误'}, 400));
    await expectLater(api.post<void>('/auth/login'),
        throwsA(predicate((error) => error.toString().contains('验证码错误'))));
    expect(storage.token, 'ruoyi-token');
  });

  test('old 401 cannot interrupt a new token still being persisted', () async {
    final gated = _GatedSecure();
    final store = TokenStorage(gated, await SharedPreferences.getInstance());
    await store.saveSession(token: 'old-token');
    final client = ApiClient.buildDio(AuthInterceptor(store));
    final pending = Completer<ResponseBody>(), started = Completer<void>();
    client.httpClientAdapter = _Adapter((_) {
      started.complete();
      return pending.future;
    });
    int expired = 0;
    final sub =
        SessionEvents.instance.onSessionExpired.listen((_) => expired++);
    final failed = expectLater(
        ApiClient(client).get<void>('/auth/getInfo'), throwsA(anything));
    await started.future;
    gated.writeGate = Completer<void>();
    final saving = store.saveSession(token: 'new-token');
    pending.complete(_body({'code': 40100}, 401));
    await failed;
    gated.writeGate!.complete();
    await saving;
    await Future<void>.delayed(Duration.zero);
    expect(store.token, 'new-token');
    expect(await gated.read(AppConstants.kAccessToken), 'new-token');
    expect(expired, 0);
    await sub.cancel();
  });
}
