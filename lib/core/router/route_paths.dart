/// 路由路径与名称常量（集中管理，避免多人合并时互相覆盖）。
///
/// 新增页面：① 在此登记 path/name；② 在 app_router.dart 注册对应 GoRoute。
/// A5 新增用户中心页面：个人资料、实名、账号安全、换绑、消息、偏好、反馈。
class RoutePath {
  RoutePath._();

  static const String splash = '/splash';

  // 认证（不属于底部导航）
  static const String login = '/login';
  static const String passwordLogin = '/login/password';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  // 登录前即可阅读的协议正文（协议勾选区域的两个链接）
  static const String agreement = '/agreement';
  static const String privacyPolicy = '/privacy-policy';

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

  // B 模块我的收藏列表（受登录守卫保护）
  static const String favorites = '/favorites';

  // B 模块创作链路（上传 / 编辑 / 草稿 / 版本 / 审核状态，受登录守卫保护）
  static const String workUpload = '/create/upload';
  static const String workEdit = '/create/edit';
  static const String draftList = '/create/drafts';
  static const String workVersions = '/create/versions';
  static const String workVersionDetail = '/create/versions/detail';
  static const String reviewStatus = '/create/review-status';
  // B 模块章节管理（接口文档无规格，按模块约定补齐；受登录守卫保护）
  static const String chapterEdit = '/create/chapter';

  // B 模块书城浏览链路（公开页，游客可浏览）
  static const String workList = '/works';
  static const String workDetail = '/work';
  static const String ranking = '/ranking';
  // 搜索页（公开可搜索；搜索历史区块仅登录可见）
  static const String search = '/search';

  // B 模块试读链路（公开页，游客可试读）
  static const String chapterList = '/chapters';
  static const String chapterRead = '/chapter';

  // B 模块漫剧（外部视频）链路（接口 2.8）
  // 详情统一用查询参数：与消息/反馈详情同风格，登录回跳只需还原整串。
  static const String dramaDetail = '/comic/drama'; // 公开：外部视频详情（2.8.15）
  static const String dramaRelatedWork = '/comic/related-work'; // 公开：找同款剧本（2.8.16）
  static const String dramaPlay = '/comic/play'; // 受保护：短剧播放（2.8.2/2.8.3/2.8.4/2.8.5）
  static const String dramaHistory = '/comic/history'; // 受保护：播放历史（2.8.6）
  static const String dramaSubscriptions = '/comic/subscriptions'; // 受保护：我的追更（2.8.14）
  static const String dramaReport = '/comic/report'; // 受保护：内容举报（2.8.17）

  /// 作品列表 URL；[title] 只用于列表页标题展示，不参与后端筛选。
  static String workListUrl({int? categoryId, int? tagId, String? keyword, String? title}) {
    final query = <String, String>{
      if (categoryId != null) 'categoryId': '$categoryId',
      if (tagId != null) 'tagId': '$tagId',
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      if (title != null && title.isNotEmpty) 'title': title,
    };
    return Uri(path: workList, queryParameters: query.isEmpty ? null : query).toString();
  }

  /// 作品详情 URL。
  static String workDetailUrl(int workId) => '$workDetail?id=$workId';

  /// 榜单 URL；[type] 取 view/favorite/sale/rating。
  static String rankingUrl(String type) => '$ranking?type=$type';

  /// 作品章节目录 URL；[title] 只用于页面标题展示。
  static String chapterListUrl(int workId, {String? title}) => Uri(
        path: chapterList,
        queryParameters: <String, String>{
          'id': '$workId',
          if (title != null && title.isNotEmpty) 'title': title,
        },
      ).toString();

  /// 章节阅读 URL；[title] 只用于页面标题展示。
  static String chapterReadUrl(int chapterId, {String? title}) => Uri(
        path: chapterRead,
        queryParameters: <String, String>{
          'id': '$chapterId',
          if (title != null && title.isNotEmpty) 'title': title,
        },
      ).toString();

  /// 外部视频详情 URL（接口 2.8.15）。
  static String dramaDetailUrl(int dramaId) => '$dramaDetail?id=$dramaId';

  /// 找同款剧本 URL（接口 2.8.16）。
  static String dramaRelatedWorkUrl(int dramaId) => '$dramaRelatedWork?id=$dramaId';

  /// 短剧播放 URL（接口 2.8.2~2.8.5）；[episodeId] 指定起始集，为空时默认第一集。
  static String dramaPlayUrl(int workId, {int? episodeId}) => Uri(
        path: dramaPlay,
        queryParameters: <String, String>{
          'id': '$workId',
          if (episodeId != null) 'episodeId': '$episodeId',
        },
      ).toString();

  /// 内容举报 URL（接口 2.8.17）；举报对象为外部视频。
  static String dramaReportUrl(int dramaId) => '$dramaReport?id=$dramaId';

  /// 编辑我的作品 URL（接口 2.9.3）。
  ///
  /// 后端没有「按 id 取本人作品详情」接口，初值全部随查询参数带入。
  static String workEditUrl({
    required int workId,
    String? title,
    String? description,
    double? price,
    int? genreId,
  }) =>
      Uri(
        path: workEdit,
        queryParameters: <String, String>{
          'id': '$workId',
          if (title != null && title.isNotEmpty) 'title': title,
          if (description != null && description.isNotEmpty) 'description': description,
          if (price != null) 'price': '$price',
          if (genreId != null) 'genreId': '$genreId',
        },
      ).toString();

  /// 版本管理 URL（接口 2.9.7 / 2.9.8）；[title] 只用于页面标题展示。
  static String workVersionsUrl(int workId, {String? title}) => Uri(
        path: workVersions,
        queryParameters: <String, String>{
          'id': '$workId',
          if (title != null && title.isNotEmpty) 'title': title,
        },
      ).toString();

  /// 版本详情 URL（接口 2.9.9）；[title] 只用于页面标题展示。
  static String workVersionDetailUrl(int versionId, {String? title}) => Uri(
        path: workVersionDetail,
        queryParameters: <String, String>{
          'id': '$versionId',
          if (title != null && title.isNotEmpty) 'title': title,
        },
      ).toString();

  /// 作品审核状态 URL（接口 2.9.6）；[title] 只用于页面标题展示。
  static String reviewStatusUrl(int workId, {String? title}) => Uri(
        path: reviewStatus,
        queryParameters: <String, String>{
          'id': '$workId',
          if (title != null && title.isNotEmpty) 'title': title,
        },
      ).toString();

  /// 章节管理 URL（接口文档无规格，按模块约定补齐）；[title] 只用于页面标题展示。
  static String chapterEditUrl(int workId, {String? title}) => Uri(
        path: chapterEdit,
        queryParameters: <String, String>{
          'id': '$workId',
          if (title != null && title.isNotEmpty) 'title': title,
        },
      ).toString();

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
  static const String passwordLogin = 'passwordLogin';
  static const String register = 'register';
  static const String forgotPassword = 'forgotPassword';
  static const String agreement = 'agreement';
  static const String privacyPolicy = 'privacyPolicy';
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
  static const String favorites = 'favorites';
  static const String workList = 'workList';
  static const String workDetail = 'workDetail';
  static const String ranking = 'ranking';
  static const String search = 'search';
  static const String chapterList = 'chapterList';
  static const String chapterRead = 'chapterRead';
  static const String dramaDetail = 'dramaDetail';
  static const String dramaRelatedWork = 'dramaRelatedWork';
  static const String dramaPlay = 'dramaPlay';
  static const String dramaHistory = 'dramaHistory';
  static const String dramaSubscriptions = 'dramaSubscriptions';
  static const String dramaReport = 'dramaReport';
  static const String workUpload = 'workUpload';
  static const String workEdit = 'workEdit';
  static const String draftList = 'draftList';
  static const String workVersions = 'workVersions';
  static const String workVersionDetail = 'workVersionDetail';
  static const String reviewStatus = 'reviewStatus';
  static const String chapterEdit = 'chapterEdit';
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
    RoutePath.favorites, // B 模块我的收藏列表（需登录）
    // B 模块创作链路（上传 / 编辑 / 草稿 / 版本 / 审核状态，需登录）；
    // 注意不含 /create 本身，避免拦截底部导航「创作」tab。
    RoutePath.workUpload,
    RoutePath.workEdit,
    RoutePath.draftList,
    RoutePath.workVersions,
    RoutePath.workVersionDetail,
    RoutePath.reviewStatus,
    RoutePath.chapterEdit, // B 模块章节管理（需登录）
    // B 模块漫剧链路（需登录）：播放/历史/追更/举报；
    // 注意不含 /comic 本身（底部导航「漫剧」tab 为公开信息流），
    // 也不含 /comic/drama、/comic/related-work（公开详情与找同款）。
    RoutePath.dramaPlay,
    RoutePath.dramaHistory,
    RoutePath.dramaSubscriptions,
    RoutePath.dramaReport,
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
