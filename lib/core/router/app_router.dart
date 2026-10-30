import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/pages/agreement_page.dart';
import '../../features/auth/pages/forgot_password_page.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/password_login_page.dart';
import '../../features/auth/pages/privacy_policy_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/bookstore/bookstore_page.dart';
import '../../features/bookstore/pages/bookshelf_page.dart';
import '../../features/bookstore/pages/chapter_list_page.dart';
import '../../features/bookstore/pages/chapter_read_page.dart';
import '../../features/bookstore/pages/favorite_list_page.dart';
import '../../features/bookstore/pages/ranking_page.dart';
import '../../features/bookstore/pages/search_page.dart';
import '../../features/bookstore/pages/work_detail_page.dart';
import '../../features/bookstore/pages/work_list_page.dart';
import '../../features/bookstore/pages/recommend_list_page.dart';
import '../../features/category/category_page.dart';
import '../../features/comic/comic_page.dart';
import '../../features/comic/pages/drama_detail_page.dart';
import '../../features/comic/pages/drama_history_page.dart';
import '../../features/comic/pages/drama_play_page.dart';
import '../../features/comic/pages/drama_related_work_page.dart';
import '../../features/comic/pages/drama_report_page.dart';
import '../../features/comic/pages/drama_subscription_page.dart';
import '../../features/create/create_page.dart';
import '../../features/create/pages/chapter_write_page.dart';
import '../../features/create/pages/work_upload_page.dart';
import '../../features/create/pages/work_version_detail_page.dart';
import '../../features/create/pages/work_workspace_page.dart';
import '../../features/create/pages/work_version_page.dart';
import '../../features/feedback/pages/feedback_create_page.dart';
import '../../features/feedback/pages/feedback_detail_page.dart';
import '../../features/feedback/pages/feedback_list_page.dart';
import '../../features/ai_creation/ai_creation_page.dart';
import '../../features/ai/ai_outline_page.dart';
import '../../features/ai/ai_write_page.dart';
import '../../features/ai/ai_polish_page.dart';
import '../../features/ai/ai_storyboard_page.dart';
import '../../features/ai/ai_record_page.dart';
import '../../features/ai/ai_chance_page.dart';
import '../../features/welfare/welfare_center_page.dart';
import '../../features/welfare/welfare_exchange_page.dart';
import '../../features/welfare/welfare_exchange_records_page.dart';
import '../../features/welfare/welfare_points_detail_page.dart';
import '../../features/seal/my_seal_page.dart';
import '../../features/seal/seal_detail_page.dart';
import '../../features/seal/seal_edit_page.dart';
import '../../features/seal/seal_upload_page.dart';
import '../../features/copyright/pages/copyright_home_page.dart';
import '../../features/copyright/pages/copyright_application_list_page.dart';
import '../../features/copyright/pages/copyright_delivery_list_page.dart';
import '../../features/copyright/pages/copyright_application_detail_page.dart';
import '../../features/copyright/pages/copyright_form_page.dart';
import '../../features/copyright/pages/copyright_certificate_list_page.dart';
import '../../features/copyright/pages/copyright_certificate_detail_page.dart';
import '../../features/income/pages/income_overview_page.dart';
import '../../features/income/pages/income_detail_page.dart';
import '../../features/income/pages/income_bill_detail_page.dart';
import '../../features/income/pages/income_settle_list_page.dart';
import '../../features/income/pages/income_settle_detail_page.dart';
import '../../features/income/pages/income_withdraw_page.dart';
import '../../features/home/home_shell.dart';
import '../../features/message/pages/message_detail_page.dart';
import '../../features/message/pages/message_list_page.dart';
import '../../features/message/pages/notification_preference_page.dart';
import '../../features/profile/pages/account_security_page.dart';
import '../../features/profile/pages/password_edit_page.dart';
import '../../features/profile/pages/phone_change_page.dart';
import '../../features/profile/pages/email_change_page.dart';
import '../../features/profile/pages/profile_edit_page.dart';
import '../../features/profile/pages/real_name_page.dart';
import '../../features/profile/pages/creator_apply_page.dart';
import '../../features/profile/pages/user_profile_page.dart';
import '../../features/profile/pages/user_follow_list_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/trade/pages/inquiry_create_page.dart';
import '../../features/trade/pages/inquiry_detail_page.dart';
import '../../features/trade/pages/inquiry_list_page.dart';
import '../../features/trade/pages/quote_records_page.dart';
import '../../features/trade/pages/order_contract_page.dart';
import '../../features/trade/pages/order_detail_page.dart';
import '../../features/trade/pages/contract_sign_page.dart';
import '../../features/trade/pages/income_overview_page.dart';
import '../../features/chat/pages/trade_session_list_page.dart';
import '../../features/chat/pages/chat_session_list_page.dart';
import '../../features/chat/pages/chat_detail_page.dart';
import '../providers/auth_providers.dart';
import 'auth_guard.dart';
import 'route_intent.dart';
import 'route_paths.dart';

const _loginRequired = '/login-required';

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
///   - 游客访问受保护路径时先确认，确认后保存 RouteIntent 并进入登录页；
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
      final isAuthPage = loc == RoutePath.login ||
          loc == RoutePath.passwordLogin ||
          loc == RoutePath.register ||
          loc == RoutePath.forgotPassword;
      final isSplash = loc == RoutePath.splash;

      switch (auth.status) {
        case AuthStatus.unknown:
          // 会话恢复中，停留在启动页
          return isSplash ? null : RoutePath.splash;
        case AuthStatus.unauthenticated:
          if (isAuthPage) return null;
          // 启动页只是会话恢复期的中转：判定完成后进入公开首页（游客可浏览书城）
          if (isSplash) return RoutePath.home;
          // 未登录：
          //   - 受保护入口（书架、收藏、福利、AI、上传、询盘、订单、合同、印章等）
          //     -> 请游客确认登录；会话失效则按原有流程直接进入登录页；
          //   - 公开入口（书城、漫剧、分类等）-> 允许游客浏览，不做跳转。
          //     规格 §8.1 只要求受保护入口走守卫，公开内容不强制登录。
          if (!ProtectedRoutes.isProtected(loc)) return null;
          if (auth.errorMessage != null) {
            _rememberIntent(ref, state);
            return RoutePath.login;
          }
          return Uri(path: _loginRequired, queryParameters: {'target': state.uri.toString()}).toString();
        case AuthStatus.authenticated:
          // 创作子页面（含深链）统一按能力准入，账号类型不赋予创作权限。
          if (loc.startsWith('${RoutePath.create}/') &&
              auth.user?.authorCapability != true) {
            return RoutePath.creatorApply;
          }
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
        path: _loginRequired,
        pageBuilder: (_, state) => NoTransitionPage(child: _LoginRequiredPage(target: state.uri.queryParameters['target'] ?? '')),
      ),
      GoRoute(
        path: RoutePath.login,
        name: RouteName.login,
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: RoutePath.passwordLogin,
        name: RouteName.passwordLogin,
        builder: (_, __) => const PasswordLoginPage(),
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
      // 协议正文：登录前即可阅读，由协议勾选区域的两个链接进入
      GoRoute(
        path: RoutePath.agreement,
        name: RouteName.agreement,
        builder: (_, __) => const AgreementPage(),
      ),
      GoRoute(
        path: RoutePath.privacyPolicy,
        name: RouteName.privacyPolicy,
        builder: (_, __) => const PrivacyPolicyPage(),
      ),
      // 底部导航：四个 tab 分支（书城 / 视频 / 分类 / 我的）+ 中间「创作」快捷入口
      // （创作不再占用分支，点击直接进入新建作品，见 HomeShell）。
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
      // ===== A6 示例业务入口（B 模块）=====
      GoRoute(
        path: RoutePath.bookshelf,
        name: RouteName.bookshelf,
        builder: (_, __) => const BookshelfPage(),
      ),
      // 我的收藏（受登录守卫保护）
      GoRoute(
        path: RoutePath.favorites,
        name: RouteName.favorites,
        builder: (_, __) => const FavoriteListPage(),
      ),
      // ===== B 模块书城浏览链路（公开页，游客可浏览）=====
      // 详情用查询参数而非路径参数：与消息/反馈详情同风格，登录回跳只需还原整串。
      GoRoute(
        path: RoutePath.workList,
        name: RouteName.workList,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return WorkListPage(
            title: query['title'],
            categoryId: int.tryParse(query['categoryId'] ?? ''),
            tagId: int.tryParse(query['tagId'] ?? ''),
            keyword: query['keyword'],
            showScope: query['showScope'],
          );
        },
      ),
      GoRoute(
        path: RoutePath.recommendList,
        name: 'recommendList',
        builder: (context, state) => const RecommendListPage(),
      ),
      GoRoute(
        path: RoutePath.workDetail,
        name: RouteName.workDetail,
        builder: (context, state) => WorkDetailPage(
          workId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.ranking,
        name: RouteName.ranking,
        builder: (context, state) => RankingPage(
          type: state.uri.queryParameters['type'],
        ),
      ),
      // 搜索页（公开页）：关键词搜索 + 搜索历史（历史区块仅登录可见）
      GoRoute(
        path: RoutePath.search,
        name: RouteName.search,
        builder: (context, state) => SearchPage(
          keyword: state.uri.queryParameters['keyword'],
        ),
      ),
      // ===== B 模块试读链路（公开页，游客可试读）=====
      GoRoute(
        path: RoutePath.chapterList,
        name: RouteName.chapterList,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return ChapterListPage(
            workId: int.tryParse(query['id'] ?? '') ?? 0,
            title: query['title'],
          );
        },
      ),
      GoRoute(
        path: RoutePath.chapterRead,
        name: RouteName.chapterRead,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return ChapterReadPage(
            chapterId: int.tryParse(query['id'] ?? '') ?? 0,
            title: query['title'],
          );
        },
      ),
      // ===== B 模块漫剧（外部视频）链路（接口 2.8）=====
      // 详情统一用查询参数 ?id=n；播放页额外支持 ?episodeId=n 指定起始集。
      GoRoute(
        path: RoutePath.dramaDetail,
        name: RouteName.dramaDetail,
        builder: (context, state) => DramaDetailPage(
          dramaId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.dramaRelatedWork,
        name: RouteName.dramaRelatedWork,
        builder: (context, state) => DramaRelatedWorkPage(
          dramaId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.dramaPlay,
        name: RouteName.dramaPlay,
        builder: (context, state) => DramaPlayPage(
          workId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
          episodeId: int.tryParse(state.uri.queryParameters['episodeId'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePath.dramaHistory,
        name: RouteName.dramaHistory,
        builder: (_, __) => const DramaHistoryPage(),
      ),
      GoRoute(
        path: RoutePath.dramaSubscriptions,
        name: RouteName.dramaSubscriptions,
        builder: (_, __) => const DramaSubscriptionPage(),
      ),
      GoRoute(
        path: RoutePath.dramaReport,
        name: RouteName.dramaReport,
        builder: (context, state) => DramaReportPage(
          dramaId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      // ===== B 模块创作链路（受登录守卫保护，见 ProtectedRoutes）=====
      // 我的作品列表（原「创作」tab 根页面，现收进「我的」页的「我的作品」入口，
      // 作为普通页面 push 打开；页面内自带游客引导与创作能力引导）。
      GoRoute(
        path: RoutePath.create,
        name: RouteName.create,
        builder: (_, __) => const CreatePage(),
      ),
      GoRoute(
        path: RoutePath.workUpload,
        name: RouteName.workUpload,
        builder: (_, __) => const WorkUploadPage(),
      ),
      GoRoute(
        path: RoutePath.workWorkspace,
        name: RouteName.workWorkspace,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return WorkWorkspacePage(
            workId: int.tryParse(query['id'] ?? '') ?? 0,
            title: query['title'],
          );
        },
      ),
      GoRoute(
        path: RoutePath.chapterWrite,
        name: RouteName.chapterWrite,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return ChapterWritePage(
            workId: int.tryParse(query['workId'] ?? '') ?? 0,
            chapterId: int.tryParse(query['chapterId'] ?? '') ?? 0,
          );
        },
      ),
      // 版本管理（/create/versions）与版本详情（/create/versions/detail）
      // 拆成两条静态路径，用查询参数区分记录，登录回跳只需还原 /path?id=n。
      GoRoute(
        path: RoutePath.workVersions,
        name: RouteName.workVersions,
        builder: (context, state) => WorkVersionPage(
          workId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
          title: state.uri.queryParameters['title'],
        ),
      ),
      GoRoute(
        path: RoutePath.workVersionDetail,
        name: RouteName.workVersionDetail,
        builder: (context, state) => WorkVersionDetailPage(
          versionId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
          title: state.uri.queryParameters['title'],
        ),
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
        path: RoutePath.creatorApply,
        name: RouteName.creatorApply,
        builder: (_, __) => const CreatorApplyPage(),
      ),
      GoRoute(
        path: RoutePath.userProfile,
        name: RouteName.userProfile,
        builder: (context, state) => UserProfilePage(
          userId: int.tryParse(state.uri.queryParameters['userId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.userFollowList,
        name: RouteName.userFollowList,
        builder: (context, state) => UserFollowListPage(
          userId: int.tryParse(state.uri.queryParameters['userId'] ?? '') ?? 0,
          showFollowing: state.uri.queryParameters['following'] == '1',
        ),
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
        path: RoutePath.emailChange,
        name: RouteName.emailChange,
        builder: (_, __) => const EmailChangePage(),
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
          source: state.uri.queryParameters['source'] == 'ANNOUNCEMENT'
              ? 'ANNOUNCEMENT'
              : 'NOTIFICATION',
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
      // ===== E 模块：AI 创作中心（受登录守卫保护）=====
      GoRoute(
        path: RoutePath.aiCenter,
        name: RouteName.aiCenter,
        builder: (_, __) => const AiCreationPage(),
      ),

      // ===== E 模块：AI 大纲 / 写作 / 润色（受登录守卫保护）=====
      GoRoute(
        path: RoutePath.aiOutline,
        name: RouteName.aiOutline,
        builder: (_, __) => const AiOutlinePage(),
      ),
      GoRoute(
        path: RoutePath.aiWrite,
        name: RouteName.aiWrite,
        builder: (_, __) => const AiWritePage(),
      ),
      GoRoute(
        path: RoutePath.aiPolish,
        name: RouteName.aiPolish,
        builder: (_, __) => const AiPolishPage(),
      ),
      GoRoute(
        path: RoutePath.aiStoryboard,
        name: RouteName.aiStoryboard,
        builder: (_, __) => const AiStoryboardPage(),
      ),
      GoRoute(
        path: RoutePath.aiRecords,
        name: RouteName.aiRecords,
        builder: (_, __) => const AiRecordPage(),
      ),
      GoRoute(
        path: RoutePath.aiOpportunity,
        name: RouteName.aiOpportunity,
        builder: (_, __) => const AiChancePage(),
      ),
      // ===== E 模块：福利中心（受登录守卫保护）=====
      GoRoute(
        path: RoutePath.welfareCenter,
        name: RouteName.welfareCenter,
        builder: (_, __) => const WelfareCenterPage(),
      ),
      GoRoute(
        path: RoutePath.welfareExchange,
        name: RouteName.welfareExchange,
        builder: (_, __) => const WelfareExchangePage(),
      ),
      GoRoute(
        path: RoutePath.welfarePointsDetail,
        name: RouteName.welfarePointsDetail,
        builder: (_, __) => const WelfarePointsDetailPage(),
      ),
      GoRoute(
        path: RoutePath.welfareExchangeRecords,
        name: RouteName.welfareExchangeRecords,
        builder: (_, __) => const WelfareExchangeRecordsPage(),
      ),
      // ===== 印章管理（受登录守卫保护）=====
      GoRoute(
        path: RoutePath.mySeal,
        name: RouteName.mySeal,
        builder: (_, __) => const MySealPage(),
      ),
      GoRoute(
        path: '${RoutePath.sealDetail}/:sealId',
        name: RouteName.sealDetail,
        builder: (context, state) {
          final sealId = int.tryParse(state.pathParameters['sealId'] ?? '') ?? 0;
          return SealDetailPage(sealId: sealId);
        },
      ),
      GoRoute(
        path: RoutePath.sealUpload,
        name: RouteName.sealUpload,
        builder: (_, __) => const SealUploadPage(),
      ),
      GoRoute(
        path: '${RoutePath.sealEdit}/:sealId',
        name: RouteName.sealEdit,
        builder: (context, state) {
          final sealId = int.tryParse(state.pathParameters['sealId'] ?? '') ?? 0;
          return SealEditPage(sealId: sealId);
        },
      ),
      // ===== C 交易域 =====
      GoRoute(
        path: RoutePath.tradeSessionList,
        name: RouteName.tradeSessionList,
        builder: (_, __) => const TradeSessionListPage(),
      ),
      GoRoute(
        path: RoutePath.incomeOverview,
        name: RouteName.incomeOverview,
        builder: (_, __) => const IncomeOverviewPage(),
      ),
      GoRoute(
        path: RoutePath.inquiryCreate,
        name: RouteName.inquiryCreate,
        builder: (context, state) => InquiryCreatePage(
          workId: int.tryParse(state.uri.queryParameters['workId'] ?? ''),
          workTitle: state.uri.queryParameters['title'],
        ),
      ),
      GoRoute(
        path: RoutePath.inquiryList,
        name: RouteName.inquiryList,
        builder: (_, __) => const InquiryListPage(),
      ),
      GoRoute(
        path: RoutePath.inquiryDetail,
        name: RouteName.inquiryDetail,
        builder: (context, state) => InquiryDetailPage(
          inquiryId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      // ===== 报价/议价 =====
      // TODO: QuoteCreatePage 页面未创建，暂时注释
      // GoRoute(
      //   path: RoutePath.quoteCreate,
      //   name: RouteName.quoteCreate,
      //   builder: (context, state) => QuoteCreatePage(
      //     inquiryId: int.tryParse(state.uri.queryParameters['inquiryId'] ?? '') ?? 0,
      //     workTitle: state.uri.queryParameters['workTitle'],
      //   ),
      // ),
      GoRoute(
        path: RoutePath.quoteList,
        name: RouteName.quoteList,
        builder: (context, state) => QuoteRecordsPage(
          inquiryId: int.tryParse(state.uri.queryParameters['inquiryId'] ?? '') ?? 0,
          workTitle: state.uri.queryParameters['workTitle'],
        ),
      ),
      // ===== 订单 =====
      GoRoute(
        path: RoutePath.orderList,
        name: RouteName.orderList,
        builder: (_, __) => const OrderContractPage(),
      ),
      GoRoute(
        path: RoutePath.orderDetail,
        name: RouteName.orderDetail,
        builder: (context, state) => OrderDetailPage(
          orderId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.contractSign,
        name: RouteName.contractSign,
        builder: (context, state) => ContractSignPage(
          orderId: int.tryParse(state.uri.queryParameters['orderId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.contractList,
        name: RouteName.contractList,
        builder: (_, __) => const OrderContractPage(initialIndex: 1),
      ),
      // ===== 版权模块（受登录守卫保护）=====
      GoRoute(
        path: RoutePath.copyrightHome,
        name: RouteName.copyrightHome,
        builder: (_, __) => const CopyrightHomePage(),
      ),
      GoRoute(
        path: RoutePath.copyrightApplicationList,
        name: RouteName.copyrightApplicationList,
        builder: (_, __) => const CopyrightApplicationListPage(),
      ),
      GoRoute(
        path: RoutePath.copyrightDeliveryList,
        name: RouteName.copyrightDeliveryList,
        builder: (_, __) => const CopyrightDeliveryListPage(),
      ),
      GoRoute(
        path: RoutePath.copyrightApplicationDetail,
        name: RouteName.copyrightApplicationDetail,
        builder: (context, state) {
          final id = int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0;
          final isDelivery = state.uri.queryParameters['type'] == 'delivery';
          return CopyrightApplicationDetailPage(
            id: id,
            type: isDelivery
                ? DetailPageType.delivery
                : DetailPageType.application,
          );
        },
      ),
      GoRoute(
        path: RoutePath.copyrightForm,
        name: RouteName.copyrightForm,
        builder: (context, state) => CopyrightFormPage(
          applyId: int.tryParse(state.uri.queryParameters['applyId'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePath.copyrightCertificateList,
        name: RouteName.copyrightCertificateList,
        builder: (_, __) => const CopyrightCertificateListPage(),
      ),
      GoRoute(
        path: RoutePath.copyrightCertificateDetail,
        name: RouteName.copyrightCertificateDetail,
        builder: (context, state) => CopyrightCertificateDetailPage(
          certId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      // ===== 我的收益（总览 + 待结算/明细/提现）=====
      GoRoute(
        path: RoutePath.myIncomeOverview,
        name: RouteName.myIncomeOverview,
        builder: (_, __) => const MyIncomeOverviewPage(),
      ),
      GoRoute(
        path: RoutePath.myIncomeSettleList,
        name: RouteName.myIncomeSettleList,
        builder: (_, __) => const MyIncomeSettleListPage(),
      ),
      GoRoute(
        path: RoutePath.myIncomeSettleDetail,
        name: RouteName.myIncomeSettleDetail,
        builder: (context, state) => MyIncomeSettleDetailPage(
          settleId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.myIncomeDetail,
        name: RouteName.myIncomeDetail,
        builder: (_, __) => const MyIncomeDetailPage(),
      ),
      GoRoute(
        path: RoutePath.myIncomeBillDetail,
        name: RouteName.myIncomeBillDetail,
        builder: (context, state) => MyIncomeBillDetailPage(
          billId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePath.myIncomeWithdraw,
        name: RouteName.myIncomeWithdraw,
        builder: (_, __) => const MyIncomeWithdrawPage(),
      ),
      // ===== A3 聊天域 =====
      GoRoute(
        path: RoutePath.chatSessionList,
        name: RouteName.chatSessionList,
        builder: (_, __) => const ChatSessionListPage(),
      ),
      GoRoute(
        path: '/chat/:sessionId',
        name: RouteName.chatDetail,
        builder: (context, state) => ChatDetailPage(
          sessionId: int.tryParse(state.pathParameters['sessionId'] ?? '') ?? 0,
        ),
      ),
    ],
  );
});

class _LoginRequiredPage extends ConsumerWidget {
  const _LoginRequiredPage({required this.target});
  final String target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void cancel() {
      if (context.canPop()) { context.pop(); } else { context.go(RoutePath.home); }
    }
    void confirm() {
      final intent = RouteIntent.fromParam(Uri.encodeComponent(target));
      final safeTarget = intent != null && ProtectedRoutes.isProtected(intent.target) ? intent.target : RoutePath.home;
      final login = AuthGuard.loginLocation(ref, safeTarget);
      if (context.canPop()) { context.pushReplacement(login); } else { context.go(login); }
    }
    return PopScope(
      canPop: context.canPop(),
      onPopInvoked: (didPop) { if (!didPop) context.go(RoutePath.home); },
      child: Scaffold(body: Center(child: AuthGuard.loginConfirmationDialog(context, onCancel: cancel, onConfirm: confirm))),
    );
  }
}

/// 保存受保护入口的定位串（含查询参数），供登录成功后回跳。
///
/// 只在没有任何待消费意图时写入：用户已经主动进入登录页（此后又被重定向回
/// 登录页）时不应覆盖既有意图，否则会把最初的深链替换成 `/login` 之下的路径。
void _rememberIntent(Ref ref, GoRouterState state) {
  final store = ref.read(routeIntentStoreProvider);
  if (store.pending != null) return;
  final intent =
      RouteIntent.fromParam(Uri.encodeComponent(state.uri.toString()));
  if (intent != null) store.save(intent);
}
