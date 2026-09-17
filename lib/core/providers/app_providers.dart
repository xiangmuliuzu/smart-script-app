import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../network/interceptors/auth_interceptor.dart';
import '../storage/token_storage.dart';

/// 框架层的依赖注入中心（Riverpod）。
///
/// 页面开发者通过 `ref.watch(xxxProvider)` 获取这些单例，不要自己 new。

/// 在 main() 中通过 `overrides` 注入真实实例。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('请在 main() 中 override 提供实例'),
);

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(ref.watch(sharedPreferencesProvider)),
);

final authInterceptorProvider = Provider<AuthInterceptor>(
  (ref) => AuthInterceptor(ref.watch(tokenStorageProvider)),
);

final dioProvider = Provider<Dio>(
  (ref) => ApiClient.buildDio(ref.watch(authInterceptorProvider)),
);

/// 唯一的网络出口。
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(dioProvider)),
);
