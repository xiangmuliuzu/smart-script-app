/// 路由路径与名称常量（集中管理，避免多人合并时互相覆盖）。
///
/// 新增页面：① 在此登记 path/name；② 在 app_router.dart 注册对应 GoRoute。
class RoutePath {
  RoutePath._();

  static const String splash = '/splash';

  // 认证（不属于底部导航）
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  // 主入口（Shell 内）：底部导航默认落在第一个分支书城，
  // 因此 home 必须是一个真实注册过的路由（不能是未注册的 '/'）。
  static const String home = '/bookstore';
  static const String bookstore = '/bookstore';
  static const String comic = '/comic';
  static const String create = '/create';
  static const String category = '/category';
  static const String profile = '/profile';
}

class RouteName {
  RouteName._();

  static const String splash = 'splash';
  static const String login = 'login';
  static const String register = 'register';
  static const String forgotPassword = 'forgotPassword';
  static const String home = 'home';
  static const String bookstore = 'bookstore';
  static const String comic = 'comic';
  static const String create = 'create';
  static const String category = 'category';
  static const String profile = 'profile';
}
