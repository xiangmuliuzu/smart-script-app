/// 接口端点常量（对照《智能剧本创作平台 接口设计文档 app 版》）。
///
/// 所有路径均为相对 [AppConfig.baseUrl]（已含 `/api/v1`）的子路径。
/// 带 `{id}` 的路径请用对应的 `xxxById(...)` 方法拼接，避免手写字符串。
/// 页面开发者**只从这里取路径**，不要在自己代码里硬编码 URL。
class ApiEndpoints {
  ApiEndpoints._();

  // ===== 2.1 登录注册 =====
  static const String smsCode = '/auth/sms-code';
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String loginSms = '/auth/login-sms';
  static const String passwordReset = '/auth/password/reset';
  static const String tokenRefresh = '/auth/refresh';

  // ===== 2.2 我的（通用）=====
  static const String userProfile = '/user/profile';
  static const String userAuth = '/user/auth'; // POST 提交 / GET 查询
  static const String notifications = '/notifications';
  static const String notificationsRead = '/notifications/read';
  static const String seals = '/seals'; // POST 提交 / GET 查询 / DELETE 停用
  static const String passwordChange = '/user/password/change';
  static const String phoneChange = '/user/phone/change';
  static const String notificationSettings = '/user/notification-settings';
  static const String feedbacks = '/feedbacks';
  static const String copyrightEvidences = '/copyright-evidences';

  // ===== 2.3 我的（创作者）=====
  static const String creatorWorks = '/creator/works';
  static String creatorWorkById(int workId) => '/creator/works/$workId';
  static const String inquiries = '/inquiries'; // GET 列表(双向) / POST 发起
  static String inquiryById(int id) => '/inquiries/$id';
  static String inquiryQuotes(int inquiryId) => '/inquiries/$inquiryId/quotes';
  static String inquiryAccept(int inquiryId) => '/inquiries/$inquiryId/accept';
  static String inquiryReject(int inquiryId) => '/inquiries/$inquiryId/reject';
  static const String chatSessions = '/chat/sessions';
  static String chatMessages(int sessionId) => '/chat/sessions/$sessionId/messages';
  static const String orders = '/orders';
  static String orderById(int orderId) => '/orders/$orderId';
  static String orderContract(int orderId) => '/orders/$orderId/contract';
  static String orderContractSign(int orderId) => '/orders/$orderId/contract/sign';
  static String orderEscrow(int orderId) => '/orders/$orderId/escrow';
  static String orderInvoice(int orderId) => '/orders/$orderId/invoice';
  static String orderPay(int orderId) => '/orders/$orderId/pay';
  static String orderCancel(int orderId) => '/orders/$orderId/cancel';
  static String orderRefund(int orderId) => '/orders/$orderId/refund';
  static String orderDelivery(int orderId) => '/orders/$orderId/delivery';
  static String workTradeConfig(int workId) => '/works/$workId/trade-config';

  // ===== 2.4 我的（甲方）=====
  static const String clientSelectionsPurchased = '/client/selections/purchased';
  static const String clientDemands = '/client/demands';
  static const String clientPayments = '/client/payments';
  static const String clientDramas = '/client/dramas';
  static String clientDramaPlayStats(int workId) => '/client/dramas/$workId/play-stats';
  static String bookContact(int workId) => '/books/$workId/contact';
  static const String cooperations = '/cooperations';

  // ===== 2.5 创作者工作台 =====
  static const String creatorStatsIncome = '/creator/stats/income';
  static const String creatorStatsOverview = '/creator/stats/overview';
  static const String creatorReviews = '/creator/reviews';
  static const String creatorBills = '/creator/bills';
  static const String creatorDashboard = '/creator/dashboard';
  static const String creatorContactProfile = '/creator/contact-profile';
  static const String creatorCooperations = '/creator/cooperations';

  // ===== 2.6 福利中心 =====
  static const String pointsAccount = '/points/account';
  static const String pointsTasks = '/points/tasks';
  static String pointsTaskClaim(int taskId) => '/points/tasks/$taskId/claim';
  static const String pointsRecords = '/points/records';
  static const String aiQuotaAccount = '/ai-quota/account';
  static const String aiQuotaRecords = '/ai-quota/records';
  static const String pointsExchangeAi = '/points/exchange-ai';
  static const String adRewardConfig = '/ads/reward-config';
  static const String adTaskReward = '/ads/task-reward';
  static const String earnOverview = '/earn/overview';

  // ===== 2.7 书城 =====
  static const String books = '/books';
  static String bookById(int workId) => '/books/$workId';
  static const String booksFilter = '/books/filter';
  static const String booksRanking = '/books/ranking';
  static String bookFreeRead(int workId) => '/books/$workId/free-read';
  static const String searchHistory = '/search-history';
  static const String favorites = '/favorites';
  static const String bookshelf = '/bookshelf';
  static const String banners = '/banners';

  // ===== 2.8 漫剧 =====
  static const String dramaFeed = '/dramas/feed';
  static const String episodes = '/episodes';
  static String episodeById(int id) => '/episodes/$id';
  static const String playProgress = '/play-progress';
  static const String playHistory = '/play-history';
  static String episodeUnlockStatus(int id) => '/episodes/$id/unlock-status';
  static String episodeUnlockPay(int id) => '/episodes/$id/unlock';
  static const String episodeComments = '/comments';
  static String episodeLike(int id) => '/episodes/$id/like';
  static const String subscriptions = '/subscriptions';
  static const String externalDramas = '/external-dramas';

  // ===== 2.9 上传和创作 =====
  static const String fileUpload = '/files/upload';
  static const String works = '/works';
  static String workById(int workId) => '/works/$workId';
  static const String drafts = '/drafts';
  static String reviewStatus(int workId) => '/works/$workId/review-status';
  static String workVersions(int workId) => '/works/$workId/versions';
  static const String aiWrite = '/ai/write';
  static const String aiPolish = '/ai/polish';
  static const String aiWriteRecords = '/ai/write/records';
  static const String aiOutline = '/ai/outline';

  // ===== 2.10 分类 =====
  static const String categories = '/categories';
  static String categoryById(int id) => '/categories/$id';
  static const String tags = '/tags';
}
