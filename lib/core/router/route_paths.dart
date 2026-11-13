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

  /// 任务广场 tab 根（大板块：广场 + 我的任务 + 发布）。
  ///
  /// 用顶层短路径而不是 `/trade/demand/...`：ProtectedRoutes 按「相等或 前缀/」匹配，
  /// 独立短路径天然不会被交易域前缀命中，游客才能直接落在 tab 上。
  static const String demandTab = '/demand';
  static const String comic = '/comic';
  static const String create = '/create';
  static const String category = '/category';
  static const String profile = '/profile';

  /// 底部导航四个内容分支的根路径（顺序与 app_router.dart 的 StatefulShellBranch 一致）。
  /// 登录回跳到这些目标时必须用 go 切分支；用 push 会把页面压进当前分支的导航栈，
  /// 出现「书城 tab 高亮、内容却是目标页」的错位（见 test/auth/auth_ui_flow_test.dart）。
  /// /comic（短剧信息流）已移出底部导航，只保留路由不做入口，因此不在此列。
  static const List<String> shellRoots = <String>[
    bookstore,
    demandTab,
    create,
    category,
    profile,
  ];

  static bool isShellRoot(String location) =>
      shellRoots.contains(Uri.parse(location).path);

  // A5 用户中心（Shell 之外的独立页面,受登录守卫保护）
  static const String profileEdit = '/profile/edit';
  /// 个人主页（自己或他人）；userId 缺省/0 表示自己。
  static const String userProfile = '/profile/home';
  /// 关注 / 粉丝列表；following=true 关注列表，false 粉丝列表。
  static const String userFollowList = '/profile/follow-list';
  /// 黑名单列表（我拉黑的用户）。
  static const String blockedUsers = '/profile/blocks';
  static String userProfileUrl(int userId) => '$userProfile?userId=$userId';
  static String userFollowListUrl(int userId, {required bool following}) =>
      '$userFollowList?userId=$userId&following=${following ? 1 : 0}';
  static const String realName = '/profile/real-name';
  static const String creatorApply = '/profile/creator-apply';
  static const String accountSecurity = '/profile/security';
  static const String phoneChange = '/profile/security/phone';
  static const String emailChange = '/profile/security/email';
  static const String passwordEdit = '/profile/security/password';
  static const String notificationPreferences = '/profile/notification-preferences';

  // A6 示例业务入口（B 模块：内容/书城），受登录与实名守卫保护
  static const String bookshelf = '/bookshelf';

  // 印章管理（用户印章上传、审核、停用）
  static const String mySeal = '/seal/my';
  static const String sealDetail = '/seal/detail';
  static const String sealUpload = '/seal/upload';
  static const String sealEdit = '/seal/edit';
  static const String sealResubmit = '/seal/resubmit';
  static const String materialPreview = '/seal/material';

  /// 印章详情 URL。
  static String sealDetailUrl(int sealId) => '$sealDetail?id=$sealId';

  /// 印章编辑 URL。
  static String sealEditUrl(int sealId) => '$sealEdit?id=$sealId';

  /// 材料预览 URL。
  static String materialPreviewUrl(int materialId) => '$materialPreview?id=$materialId';

  // ===== 版权模块（受登录守卫保护）=====
  static const String copyrightHome = '/copyright/home';
  static const String copyrightApplicationList = '/copyright/application/list';
  static const String copyrightDeliveryList = '/copyright/delivery/list';
  static const String copyrightApplicationDetail = '/copyright/application/detail';
  static const String copyrightForm = '/copyright/form';
  static const String copyrightPay = '/copyright/pay';
  static const String copyrightCertificateList = '/copyright/certificate/list';
  static const String copyrightCertificateDetail = '/copyright/certificate/detail';
  static const String buyerCopyrightDetail = '/copyright/certificate/purchased';

  /// 版权首页 URL
  static String copyrightHomeUrl() => copyrightHome;

  /// 版权申请列表 URL
  static String copyrightApplicationListUrl() => copyrightApplicationList;

  /// 版权交割列表 URL
  static String copyrightDeliveryListUrl() => copyrightDeliveryList;

  /// 版权申请详情 URL
  static String copyrightApplicationDetailUrl(int applyId) => 
      '$copyrightApplicationDetail?id=$applyId';

  /// 版权申请表单 URL（新建或编辑）
  static String copyrightFormUrl({int? applyId}) => Uri(
        path: copyrightForm,
        queryParameters: applyId != null ? {'applyId': '$applyId'} : null,
      ).toString();

  /// 版权登记费支付 URL
  static String copyrightPayUrl(int payOrderId, {double? feeAmount}) => Uri(
        path: copyrightPay,
        queryParameters: {
          'id': '$payOrderId',
          if (feeAmount != null) 'amount': feeAmount.toStringAsFixed(2),
        },
      ).toString();

  /// 版权证书列表 URL
  static String copyrightCertificateListUrl() => copyrightCertificateList;

  /// 版权证书详情 URL
  static String copyrightCertificateDetailUrl(int certId) =>
      '$copyrightCertificateDetail?id=$certId';

  /// 购买获得的版权材料详情 URL
  static String buyerCopyrightDetailUrl(int fileId) =>
      '$buyerCopyrightDetail?id=$fileId';

  // ===== 我的收益（独立于交易管理「作者收益」）=====
  static const String myIncomeOverview = '/income/overview';
  static const String myIncomeDetail = '/income/detail';
  static const String myIncomeBillDetail = '/income/bill';
  static const String myIncomeSettleList = '/income/settle';
  static const String myIncomeSettleDetail = '/income/settle/detail';
  static const String myIncomeWithdraw = '/income/withdraw';

  static String myIncomeBillDetailUrl(int billId) =>
      '$myIncomeBillDetail?id=$billId';

  static String myIncomeSettleDetailUrl(int settleId) =>
      '$myIncomeSettleDetail?id=$settleId';

  // B 模块我的收藏列表（受登录守卫保护）
  static const String favorites = '/favorites';

  // B 模块创作链路（新建作品 / 工作台 / 章节写作 / 版本，受登录守卫保护）
  static const String workUpload = '/create/upload';
  static const String workWorkspace = '/create/workspace';
  static const String chapterWrite = '/create/chapter/write';
  static const String workVersions = '/create/versions';
  static const String workVersionDetail = '/create/versions/detail';

  // B 模块书城浏览链路（公开页，游客可浏览）
  static const String workList = '/works';
  static const String recommendList = '/recommend-list';
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
  /// [sort] 为初始排序（值与后端 normalizeSort 白名单一致，如 view/favorite/...）；
  /// 不传时列表页默认最新排序，保持既有行为不变。
  static String workListUrl({int? tagId, String? keyword, String? title, String? sort}) {
    final query = <String, String>{
      if (tagId != null) 'tagId': '$tagId',
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      if (title != null && title.isNotEmpty) 'title': title,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
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

  /// 作品工作台 URL（写作范式：章节 / 设置 / 发布 三 Tab）。
  ///
  /// 工作台内部以 A 套 `GET /users/me/works/{workId}` 为单一数据源，
  /// 只需 workId；[title] 仅用于详情加载完成前的 AppBar 占位。
  static String workWorkspaceUrl({required int workId, String? title}) => Uri(
        path: workWorkspace,
        queryParameters: <String, String>{
          'id': '$workId',
          if (title != null && title.isNotEmpty) 'title': title,
        },
      ).toString();

  /// 章节写作编辑器 URL；[chapterId] 为 0 或不传时为新建模式。
  static String chapterWriteUrl({required int workId, int? chapterId}) => Uri(
        path: chapterWrite,
        queryParameters: <String, String>{
          'workId': '$workId',
          if (chapterId != null && chapterId > 0) 'chapterId': '$chapterId',
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

  // ===== 作品推广（付费推荐，受登录守卫保护）=====
  /// 推广路径前缀（仅用于登录守卫登记，本身不注册页面）。
  static const String promotion = '/promotion';
  static const String promotionCenter = '/promotion/center';
  static const String promotionCreate = '/promotion/create';
  static const String promotionDetail = '/promotion/detail';
  static const String promotionPay = '/promotion/pay';

  static String promotionDetailUrl(int applyId) =>
      '$promotionDetail?id=$applyId';

  static String promotionPayUrl(int applyId) => '$promotionPay?id=$applyId';

  // A5 消息中心（列表与详情用查询参数区分，便于登录回跳时整串还原）
  static const String messages = '/profile/messages';
  static const String messageDetail = '/profile/messages/detail';
  static const String feedback = '/profile/feedback';
  static const String feedbackDetail = '/profile/feedback/detail';
  static const String feedbackCreate = '/profile/feedback/create';

  // ===== C 交易域（受登录守卫保护）=====
  // 交易管理
  static const String tradeManagement = '/trade/management';
  static const String tradeSessionList = '/trade/session/list';
  // 财务
  static const String finance = '/trade/finance';
  static const String incomeOverview = '/trade/finance/income';
  static const String financeOrders = '/trade/finance/orders';
  static const String financeContracts = '/trade/finance/contracts';
  // 询盘
  static const String inquiryCreate = '/trade/inquiry/create';
  static const String inquiryList = '/trade/inquiry/list';
  static const String inquiryDetail = '/trade/inquiry/detail';
  // 报价
  static const String quoteCreate = '/trade/quote/create';
  static const String quoteList = '/trade/quote/list';
  static const String counterOffer = '/trade/quote/counter-offer';
  // 订单
  static const String orderList = '/trade/order/list';
  static const String orderDetail = '/trade/order/detail';
  static const String orderCancel = '/trade/order/cancel';
  // 合同签署
  static const String contractList = '/trade/contract/list';
  static const String contractSign = '/trade/contract/sign';
  // 合作记录
  static const String cooperationCreate = '/trade/cooperation/create';
  static const String followUpList = '/trade/follow-up/list';
  // 需求
  static const String demandList = '/trade/demand/list';
  static const String demandDetail = '/trade/demand/detail';
  static const String demandPost = '/trade/demand/post';
  static const String demandMyTasks = '/trade/demand/my-tasks';
  static const String demandStageDeliver = '/trade/demand/stage-deliver';
  static const String demandDeliverableWork = '/trade/demand/deliverable-work';
  static const String demandSourceScript = '/trade/demand/source-script';

  static String demandDetailUrl(int demandId) => '$demandDetail?id=$demandId';
  /// 编辑已有任务（发布页带 id 进入编辑模式）。
  static String demandPostEditUrl(int demandId) => '$demandPost?id=$demandId';
  /// 提交本轮交付物（全屏页：选作品+说明+提交）。
  static String demandStageDeliverUrl(int demandId, int stageId, int stageOrder) =>
      '$demandStageDeliver?demandId=$demandId&stageId=$stageId&order=$stageOrder';
  /// 验收查阅交付作品（全屏页：发布者看本轮已交集数的正文）。
  static String demandDeliverableWorkUrl(int demandId, int stageId, int stageOrder) =>
      '$demandDeliverableWork?demandId=$demandId&stageId=$stageId&order=$stageOrder';
  /// 源剧本查阅（分镜类任务，接单前评估用；任何登录用户可看全本）。
  static String demandSourceScriptUrl(int demandId) =>
      '$demandSourceScript?demandId=$demandId';
  // 线上沟通（聊天，接入 A3）
  static const String tradeChat = '/trade/chat';
  // 聊天会话列表
  static const String chatSessionList = '/chat';
  // 聊天详情页
  static String chatDetail(int sessionId) => '/chat/$sessionId';

  /// App 端 E 模块：福利中心与 AI 创作。
  static const String welfareCenter = '/welfare';
  static const String welfareExchange = '/welfare/exchange';
  static const String welfareRecharge = '/welfare/recharge';
  static const String welfarePointsDetail = '/welfare/points-detail';
  static const String welfareExchangeRecords = '/welfare/exchange-records';
  static const String aiCenter = '/ai';
  static const String aiOutline = '/ai/outline';

  /// AI 创作页（设定 → 大纲 → 章节，创作链路专用）。
  static const String aiCreate = '/ai/create';
  static const String aiWrite = '/ai/write';
  static const String aiPolish = '/ai/polish';
  static const String aiStoryboard = '/ai/storyboard';
  static const String aiRecords = '/ai/records';
  static const String aiOpportunity = '/ai/opportunity';
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
  static const String demandTab = 'demandTab';
  static const String comic = 'comic';
  static const String create = 'create';
  static const String category = 'category';
  static const String profile = 'profile';

  static const String profileEdit = 'profileEdit';
  static const String userProfile = 'userProfile';
  static const String userFollowList = 'userFollowList';
  static const String blockedUsers = 'blockedUsers';
  static const String realName = 'realName';
  static const String creatorApply = 'creatorApply';
  static const String accountSecurity = 'accountSecurity';
  static const String phoneChange = 'phoneChange';
  static const String emailChange = 'emailChange';
  static const String passwordEdit = 'passwordEdit';
  static const String notificationPreferences = 'notificationPreferences';
  static const String bookshelf = 'bookshelf';
  static const String favorites = 'favorites';
  static const String mySeal = 'mySeal';
  static const String sealDetail = 'sealDetail';
  static const String sealUpload = 'sealUpload';
  static const String sealEdit = 'sealEdit';
  static const String sealResubmit = 'sealResubmit';
  static const String materialPreview = 'materialPreview';
  
  // ===== 版权模块 =====
  static const String copyrightHome = 'copyrightHome';
  static const String copyrightApplicationList = 'copyrightApplicationList';
  static const String copyrightDeliveryList = 'copyrightDeliveryList';
  static const String copyrightApplicationDetail = 'copyrightApplicationDetail';
  static const String copyrightForm = 'copyrightForm';
  static const String copyrightPay = 'copyrightPay';
  static const String copyrightCertificateList = 'copyrightCertificateList';
  static const String copyrightCertificateDetail = 'copyrightCertificateDetail';
  static const String buyerCopyrightDetail = 'buyerCopyrightDetail';

  // ===== 我的收益 =====
  static const String myIncomeOverview = 'myIncomeOverview';
  static const String myIncomeDetail = 'myIncomeDetail';
  static const String myIncomeBillDetail = 'myIncomeBillDetail';
  static const String myIncomeSettleList = 'myIncomeSettleList';
  static const String myIncomeSettleDetail = 'myIncomeSettleDetail';
  static const String myIncomeWithdraw = 'myIncomeWithdraw';
  
  static const String workList = 'workList';
  static const String recommendList = 'recommendList';
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
  static const String workWorkspace = 'workWorkspace';
  static const String chapterWrite = 'chapterWrite';
  static const String workVersions = 'workVersions';
  static const String workVersionDetail = 'workVersionDetail';

  // ===== 作品推广 =====
  static const String promotionCenter = 'promotionCenter';
  static const String promotionCreate = 'promotionCreate';
  static const String promotionDetail = 'promotionDetail';
  static const String promotionPay = 'promotionPay';

  static const String messages = 'messages';
  static const String messageDetail = 'messageDetail';
  static const String feedback = 'feedback';
  static const String feedbackDetail = 'feedbackDetail';
  static const String feedbackCreate = 'feedbackCreate';

  // ===== C 交易域 =====
  static const String tradeManagement = 'tradeManagement';
  static const String tradeSessionList = 'tradeSessionList';
  static const String finance = 'finance';
  static const String incomeOverview = 'incomeOverview';
  static const String financeOrders = 'financeOrders';
  static const String financeContracts = 'financeContracts';
  static const String inquiryCreate = 'inquiryCreate';
  static const String inquiryList = 'inquiryList';
  static const String inquiryDetail = 'inquiryDetail';
  static const String quoteCreate = 'quoteCreate';
  static const String quoteList = 'quoteList';
  static const String counterOffer = 'counterOffer';
  static const String orderList = 'orderList';
  static const String orderDetail = 'orderDetail';
  static const String orderCancel = 'orderCancel';
  static const String contractList = 'contractList';
  static const String contractSign = 'contractSign';
  static const String cooperationCreate = 'cooperationCreate';
  static const String followUpList = 'followUpList';
  static const String demandList = 'demandList';
  static const String demandDetail = 'demandDetail';
  static const String demandPost = 'demandPost';
  static const String demandMyTasks = 'demandMyTasks';
  static const String demandStageDeliver = 'demandStageDeliver';
  static const String demandDeliverableWork = 'demandDeliverableWork';
  static const String demandSourceScript = 'demandSourceScript';
  static const String tradeChat = 'tradeChat';
  // 聊天
  static const String chatSessionList = 'chatSessionList';
  static const String chatDetail = 'chatDetail';

  // ===== E 模块：福利中心与 AI 创作 =====
  static const String welfareCenter = 'welfareCenter';
  static const String welfareExchange = 'welfareExchange';
  static const String welfareRecharge = 'welfareRecharge';
  static const String welfarePointsDetail = 'welfarePointsDetail';
  static const String welfareExchangeRecords = 'welfareExchangeRecords';
  static const String aiCenter = 'aiCenter';
  static const String aiOutline = 'aiOutline';
  static const String aiCreate = 'aiCreate';
  static const String aiWrite = 'aiWrite';
  static const String aiPolish = 'aiPolish';
  static const String aiStoryboard = 'aiStoryboard';
  static const String aiRecords = 'aiRecords';
  static const String aiOpportunity = 'aiOpportunity';
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
    // B 模块创作链路（新建作品 / 工作台 / 版本，需登录）；
    // 注意不含 /create 本身，避免拦截底部导航「创作」tab。
    RoutePath.workUpload,
    RoutePath.workWorkspace,
    RoutePath.chapterWrite,
    RoutePath.workVersions,
    RoutePath.workVersionDetail,
    // B 模块漫剧链路（需登录）：播放/历史/追更/举报；
    // 注意不含 /comic 本身（短剧信息流为公开页），也不含 /comic/drama、/comic/related-work
    // （公开详情与找同款）。/comic 已退出底部导航，只保留路由供深链直达，没有站内入口。
    RoutePath.dramaPlay,
    RoutePath.dramaHistory,
    RoutePath.dramaSubscriptions,
    RoutePath.dramaReport,
    // C 交易域（询盘/报价/订单/合作，需登录）
    RoutePath.inquiryCreate,
    RoutePath.inquiryList,
    RoutePath.inquiryDetail,
    RoutePath.quoteList,
    RoutePath.counterOffer,
    RoutePath.orderList,
    RoutePath.orderDetail,
    RoutePath.orderCancel,
    // 合同签署（需登录）
    RoutePath.contractList,
    RoutePath.contractSign,
    RoutePath.cooperationCreate,
    RoutePath.followUpList,
    // 任务广场（底部导航大板块）：tab 根 /demand 与广场/详情不登记，游客可逛；
    // /trade/demand/list 只是指向 tab 根的兼容跳转，同样不设闸。
    // 需要登录的是「动作与个人视角」：发布、我的任务、交付验收、源剧本。
    RoutePath.demandPost,
    RoutePath.demandMyTasks,
    RoutePath.demandStageDeliver,
    RoutePath.demandDeliverableWork,
    RoutePath.demandSourceScript,
    RoutePath.tradeChat,
    // 聊天（需登录）
    RoutePath.chatSessionList,
    // 财务（需登录）
    RoutePath.incomeOverview,
    // E 模块：福利中心与 AI 创作（需登录）
    RoutePath.welfareCenter,
    RoutePath.welfareRecharge,
    RoutePath.aiCenter,
    RoutePath.aiCreate,
    // 印章管理（需登录）
    RoutePath.mySeal,
    // 版权模块（需登录）
    RoutePath.copyrightHome,
    RoutePath.copyrightApplicationList,
    RoutePath.copyrightDeliveryList,
    RoutePath.copyrightForm,
    RoutePath.copyrightPay,
    RoutePath.copyrightCertificateList,
    RoutePath.buyerCopyrightDetail,
    // 我的收益（需登录）
    RoutePath.myIncomeOverview,
    RoutePath.myIncomeDetail,
    RoutePath.myIncomeBillDetail,
    RoutePath.myIncomeSettleList,
    RoutePath.myIncomeSettleDetail,
    RoutePath.myIncomeWithdraw,
    // 作品推广（需登录）
    RoutePath.promotion,
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
    RoutePath.emailChange,
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
