/// A3-AUTH-CONTRACT-v1 与 A5-USER-CENTER-CONTRACT-v1 端点
/// （相对 [AppConfig.baseUrl]，已含 `/api/v1`）。
class ApiEndpoints {
  ApiEndpoints._();

  // ===== A3 认证契约 =====
  static const String smsSend = '/auth/sms/send';
  static const String smsLogin = '/auth/sms/login';
  static const String passwordLogin = '/auth/password/login';
  static const String register = '/auth/register';
  static const String tokenRefresh = '/auth/token/refresh';
  static const String logout = '/auth/logout';
  static const String me = '/auth/me';
  static const String passwordSet = '/auth/password/set';
  static const String passwordChange = '/auth/password/change';
  static const String passwordReset = '/auth/password/reset';
  static const String agreements = '/auth/agreements';
  static String oauthLogin(String provider) => '/auth/oauth/$provider/login';

  // ===== A5 用户中心契约：个人资料与账号安全 =====
  static const String myProfile = '/users/me/profile';
  static const String myRealName = '/users/me/real-name';
  static const String myRealNameResubmit = '/users/me/real-name/resubmit';
  static const String phoneChangeOldSend = '/users/me/phone/change/old/send';
  static const String phoneChangeOldVerify = '/users/me/phone/change/old/verify';
  static const String phoneChangeNewSend = '/users/me/phone/change/new/send';
  static const String phoneChangeConfirm = '/users/me/phone/change/confirm';
  static const String myNotificationPreferences = '/users/me/notification-preferences';

  // ===== A5 用户中心契约：消息中心 =====
  static const String messages = '/messages';
  static const String messagesUnreadCount = '/messages/unread-count';
  static const String messagesReadAll = '/messages/read-all';
  static String messageById(int messageId) => '/messages/$messageId';
  static String messageRead(int messageId) => '/messages/$messageId/read';

  // ===== A5 用户中心契约：意见反馈 =====
  static const String feedback = '/feedback';
  static String feedbackById(int feedbackId) => '/feedback/$feedbackId';

  /// App 域头像上传（multipart，字段名 `file`）。
  ///
  /// 不走平台原生的 `/common/upload`：该端点属于 PC 凭证链，App Token 无法通过鉴权，
  /// 且响应是若依 AjaxResult 而非 App 信封。
  static const String myAvatar = '/users/me/avatar';

  // ===== 业务端点（非 A3 认证范围，保持既有命名） =====
  static const String userProfile = '/user/profile';
  static const String userAuth = '/user/auth';
  static const String notifications = '/notifications';
  static const String notificationsRead = '/notifications/read';
  static const String seals = '/seals';
  static const String phoneChange = '/user/phone/change';
  static const String notificationSettings = '/user/notification-settings';
  static const String feedbacks = '/feedbacks';
  static const String copyrightEvidences = '/copyright-evidences';
  static const String creatorWorks = '/creator/works';
  static String creatorWorkById(int workId) => '/creator/works/$workId';
  static const String inquiries = '/inquiries';
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
  static const String clientSelectionsPurchased = '/client/selections/purchased';
  static const String clientDemands = '/client/demands';
  static const String clientPayments = '/client/payments';
  static const String clientDramas = '/client/dramas';
  static String clientDramaPlayStats(int workId) => '/client/dramas/$workId/play-stats';
  static String bookContact(int workId) => '/books/$workId/contact';
  static const String cooperations = '/cooperations';
  static const String creatorStatsIncome = '/creator/stats/income';
  static const String creatorStatsOverview = '/creator/stats/overview';
  static const String creatorReviews = '/creator/reviews';
  static const String creatorBills = '/creator/bills';
  static const String creatorDashboard = '/creator/dashboard';
  static const String creatorContactProfile = '/creator/contact-profile';
  static const String creatorCooperations = '/creator/cooperations';
  static const String pointsAccount = '/points/account';
  static const String pointsTasks = '/points/tasks';
  static String pointTaskClaim(int taskId) => '/points/tasks/$taskId/claim';
  static const String pointsRecords = '/points/records';
  static const String aiQuotaAccount = '/ai-quota/account';
  static const String aiQuotaRecords = '/ai-quota/records';
  static const String pointsExchangeAi = '/points/exchange-ai';
  static const String adRewardConfig = '/ads/reward-config';
  static const String adTaskReward = '/ads/task-reward';
  static const String earnOverview = '/earn/overview';
  static const String books = '/books';
  static String bookById(int workId) => '/books/$workId';
  static const String booksFilter = '/books/filter';
  static const String booksRanking = '/books/ranking';
  static String bookFreeRead(int workId) => '/books/$workId/free-read';
  static const String searchHistory = '/search-history';
  static const String favorites = '/favorites';
  static const String bookshelf = '/bookshelf';
  static const String banners = '/banners';
  static const String dramaFeed = '/dramas/feed';
  static const String episodes = '/episodes';
  static String episodeById(int id) => '/episodes/$id';
  static const String playProgress = '/play-progress';
  static const String playHistory = '/play-history';
  static String episodeUnlockStatus(int id) => '/episodes/$id/unlock-status';
  static String episodeUnlockPay(int id) => '/episodes/$id/unlock';
  static const String episodeComments = '/comments';
  static String episodeLike(int id) => '/comments/$id/like';
  static const String subscriptions = '/subscriptions';
  static const String externalDramas = '/external-dramas';
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
  static const String categories = '/categories';
  static String categoryById(int id) => '/categories/$id';
  static const String tags = '/tags';
}
