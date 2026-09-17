import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/bookstore/bookstore_page.dart';
import '../../features/category/category_page.dart';
import '../../features/comic/comic_page.dart';
import '../../features/create/create_page.dart';
import '../../features/home/home_shell.dart';
import '../../features/profile/profile_page.dart';
import '../../features/splash/splash_page.dart';
import '../providers/auth_providers.dart';
import 'route_paths.dart';

/// 把 Riverpod 的 auth 状态变化桥接给 GoRouter 的 refreshListenable。
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    _sub = ref.listen(
      authControllerProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

/// 全局路由（含登录态重定向 + 底部导航 Shell）。
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePath.splash,
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final isAuthPage =
          loc == RoutePath.login || loc == RoutePath.register || loc == RoutePath.forgotPassword;
      final isSplash = loc == RoutePath.splash;

      switch (auth.status) {
        case AuthStatus.unknown:
          // 会话恢复中，停留在启动页
          return isSplash ? null : RoutePath.splash;
        case AuthStatus.unauthenticated:
          return isAuthPage ? null : RoutePath.login;
        case AuthStatus.authenticated:
          return (isAuthPage || isSplash) ? RoutePath.home : null;
      }
    },
    routes: [
      GoRoute(
        path: RoutePath.splash,
        name: RouteName.splash,
        builder: (_, __) => const SplashPage(),
      ),
      GoRoute(
        path: RoutePath.login,
        name: RouteName.login,
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: RoutePath.register,
        name: RouteName.register,
        builder: (_, __) => const RegisterPage(),
      ),
      // 底部导航五格：书城 / 漫剧 / 创作(+) / 分类 / 我的
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePath.bookstore,
                name: RouteName.bookstore,
                builder: (_, __) => const BookstorePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePath.comic,
                name: RouteName.comic,
                builder: (_, __) => const ComicPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePath.create,
                name: RouteName.create,
                builder: (_, __) => const CreatePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePath.category,
                name: RouteName.category,
                builder: (_, __) => const CategoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePath.profile,
                name: RouteName.profile,
                builder: (_, __) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
