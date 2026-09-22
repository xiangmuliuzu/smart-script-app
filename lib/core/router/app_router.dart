import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/pages/forgot_password_page.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/bookstore/bookstore_page.dart';
import '../../features/category/category_page.dart';
import '../../features/comic/comic_page.dart';
import '../../features/create/create_page.dart';
import '../../features/feedback/pages/feedback_create_page.dart';
import '../../features/feedback/pages/feedback_detail_page.dart';
import '../../features/feedback/pages/feedback_list_page.dart';
import '../../features/home/home_shell.dart';
import '../../features/message/pages/message_detail_page.dart';
import '../../features/message/pages/message_list_page.dart';
import '../../features/message/pages/notification_preference_page.dart';
import '../../features/profile/pages/account_security_page.dart';
import '../../features/profile/pages/password_edit_page.dart';
import '../../features/profile/pages/phone_change_page.dart';
import '../../features/profile/pages/profile_edit_page.dart';
import '../../features/profile/pages/real_name_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/splash/splash_page.dart';
import '../providers/auth_providers.dart';
import 'route_intent.dart';
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

/// 全局路由（含登录态重定向 + 底部导航 Shell + A5 用户中心页面）。
///
/// 守卫策略（规格 §8.1）：
///   - 受保护路径未登录时保存结构化 RouteIntent 后进入登录页；
///   - 登录成功后由登录页消费一次意图回跳，非法或不可恢复时回安全默认首页；
///   - 用户主动点击登录入口不产生回跳（URL 无 redirect 参数即不产生意图）。
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
          if (isAuthPage) return null;
          // 受保护入口：保存回跳意图后进入登录页
          if (ProtectedRoutes.isProtected(loc)) {
            _rememberIntent(ref, state);
          }
          return RoutePath.login;
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
      GoRoute(
        path: RoutePath.forgotPassword,
        name: RouteName.forgotPassword,
        builder: (_, __) => const ForgotPasswordPage(),
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
      // ===== A5 用户中心 =====
      // 列表与详情拆成两个静态路径，用查询参数区分记录：
      // 登录回跳只需还原 `/path?id=n` 一种形式，不必重建路径参数。
      GoRoute(
        path: RoutePath.profileEdit,
        name: RouteName.profileEdit,
        builder: (_, __) => const ProfileEditPage(),
      ),
      GoRoute(
        path: RoutePath.realName,
        name: RouteName.realName,
        builder: (_, __) => const RealNamePage(),
      ),
      GoRoute(
        path: RoutePath.accountSecurity,
        name: RouteName.accountSecurity,
        builder: (_, __) => const AccountSecurityPage(),
      ),
      GoRoute(
        path: RoutePath.phoneChange,
        name: RouteName.phoneChange,
        builder: (_, __) => const PhoneChangePage(),
      ),
      GoRoute(
        path: RoutePath.passwordEdit,
        name: RouteName.passwordEdit,
        builder: (context, state) => PasswordEditPage(
          hasPassword: state.uri.queryParameters['hasPassword'] == '1',
        ),
      ),
      GoRoute(
        path: RoutePath.notificationPreferences,
        name: RouteName.notificationPreferences,
        builder: (_, __) => const NotificationPreferencePage(),
      ),
      GoRoute(
        path: RoutePath.messages,
        name: RouteName.messages,
        builder: (_, __) => const MessageListPage(),
      ),
      GoRoute(
        path: RoutePath.messageDetail,
        name: RouteName.messageDetail,
        builder: (context, state) => MessageDetailPage(
          messageId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.feedback,
        name: RouteName.feedback,
        builder: (_, __) => const FeedbackListPage(),
      ),
      GoRoute(
        path: RoutePath.feedbackCreate,
        name: RouteName.feedbackCreate,
        builder: (_, __) => const FeedbackCreatePage(),
      ),
      GoRoute(
        path: RoutePath.feedbackDetail,
        name: RouteName.feedbackDetail,
        builder: (context, state) => FeedbackDetailPage(
          feedbackId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
    ],
  );
});

/// 保存受保护入口的定位串（含查询参数），供登录成功后回跳。
///
/// 只在没有任何待消费意图时写入：用户已经主动进入登录页（此后又被重定向回
/// 登录页）时不应覆盖既有意图，否则会把最初的深链替换成 `/login` 之下的路径。
void _rememberIntent(Ref ref, GoRouterState state) {
  final store = ref.read(routeIntentStoreProvider);
  if (store.pending != null) return;
  final intent = RouteIntent.fromParam(Uri.encodeComponent(state.uri.toString()));
  if (intent != null) store.save(intent);
}
