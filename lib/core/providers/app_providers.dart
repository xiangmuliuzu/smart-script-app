import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../network/interceptors/auth_interceptor.dart';
import '../storage/secure_token_storage.dart';
import '../storage/token_storage.dart';
import '../../features/auth/data/auth_repository.dart';

/// Framework DI center (Riverpod).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('请在 main() 中 override 提供实例'),
);

final secureTokenStorageProvider = Provider<TokenSecureStorage>(
  (ref) => FlutterSecureTokenStorage(),
);

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(
    ref.watch(secureTokenStorageProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);

/// Breaks the interceptor ↔ repository cycle via a mutable holder.
class AuthNetworkGraph {
  AuthNetworkGraph._({
    required this.storage,
    required this.repository,
    required this.interceptor,
    required this.apiClient,
  });

  final TokenStorage storage;
  final AuthRepository repository;
  final AuthInterceptor interceptor;
  final ApiClient apiClient;

  factory AuthNetworkGraph.create(TokenStorage storage) {
    late AuthRepository repository;
    late AuthInterceptor interceptor;
    late ApiClient apiClient;
    interceptor = AuthInterceptor(
      storage,
      () => repository,
      () => interceptor.refreshCountForTest,
    );
    final dio = ApiClient.buildDio(interceptor);
    apiClient = ApiClient(dio);
    repository = AuthRepository(apiClient);
    return AuthNetworkGraph._(
      storage: storage,
      repository: repository,
      interceptor: interceptor,
      apiClient: apiClient,
    );
  }
}

final authNetworkGraphProvider = Provider<AuthNetworkGraph>(
  (ref) => AuthNetworkGraph.create(ref.watch(tokenStorageProvider)),
);

final authInterceptorProvider = Provider<AuthInterceptor>(
  (ref) => ref.watch(authNetworkGraphProvider).interceptor,
);

final dioProvider = Provider<Dio>(
  (ref) => ref.watch(authNetworkGraphProvider).apiClient.dioForTest,
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ref.watch(authNetworkGraphProvider).apiClient,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(authNetworkGraphProvider).repository,
);
