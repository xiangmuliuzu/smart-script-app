/// 路由路径与名称常量（集中管理，避免多人合并时互相覆盖）。
///
/// 新增页面：① 在此登记 path/name；② 在 app_router.dart 注册对应 GoRoute。
/// A5 新增用户中心页面：个人资料、实名、账号安全、换绑、消息、偏好、反馈。
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

  // A5 用户中心（Shell 之外的独立页面，受登录守卫保护）
  static const String profileEdit = '/profile/edit';
  static const String realName = '/profile/real-name';
  static const String accountSecurity = '/profile/security';
  static const String phoneChange = '/profile/security/phone';
  static const String passwordEdit = '/profile/security/password';
  static const String notificationPreferences = '/profile/notification-preferences';

  // A6 示例业务入口（B 模块：内容/书城），受登录与实名守卫保护
  static const String bookshelf = '/bookshelf';

  // A5 消息中心（列表与详情用查询参数区分，便于登录回跳时整串还原）
  static const String messages = '/profile/messages';
  static const String messageDetail = '/profile/messages/detail';
  static const String feedback = '/profile/feedback';
  static const String feedbackDetail = '/profile/feedback/detail';
  static const String feedbackCreate = '/profile/feedback/create';
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

  static const String profileEdit = 'profileEdit';
  static const String realName = 'realName';
  static const String accountSecurity = 'accountSecurity';
  static const String phoneChange = 'phoneChange';
  static const String passwordEdit = 'passwordEdit';
  static const String notificationPreferences = 'notificationPreferences';
  static const String bookshelf = 'bookshelf';
  static const String messages = 'messages';
  static const String messageDetail = 'messageDetail';
  static const String feedback = 'feedback';
  static const String feedbackDetail = 'feedbackDetail';
  static const String feedbackCreate = 'feedbackCreate';
}

/// 需要登录才能访问的路径前缀（规格 §8.1 守卫清单）。
///
/// 收藏、书架、福利、AI、上传、询盘、订单、合同和印章等 B/C/D/E 入口
/// 后续接入时沿用 [RoutePath.profile] 之外的前缀，在此登记即可。
class ProtectedRoutes {
  ProtectedRoutes._();

  /// 需要登录的路径前缀。
  static const List<String> prefixes = <String>[
    RoutePath.profile, // 我的及用户中心全部子页面
    RoutePath.bookshelf, // A6 示例（B 模块）受保护入口
  ];

  static bool isProtected(String location) {
    final path = Uri.parse(location).path;
    for (final prefix in prefixes) {
      if (path == prefix || path.startsWith('$prefix/')) return true;
    }
    return false;
  }

  /// 强制退出后不允许自动回跳的路径前缀（规格 §8.1 末条）：
  /// 换绑、修改密码等敏感提交页在会话失效后不应被自动重放。
  static const List<String> noResumePrefixes = <String>[
    RoutePath.phoneChange,
    RoutePath.accountSecurity,
    RoutePath.passwordEdit,
  ];

  static bool canResume(String location) {
    final path = Uri.parse(location).path;
    for (final prefix in noResumePrefixes) {
      if (path == prefix || path.startsWith('$prefix/')) return false;
    }
    return true;
  }
}
