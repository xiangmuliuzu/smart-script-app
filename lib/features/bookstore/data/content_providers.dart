import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../user_center/data/paged_data.dart';
import 'bookstore_models.dart';
import 'content_repository.dart';

/// B 模块书城依赖注入（复用框架层网络栈，不新建 Dio）。

final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepository(ref.watch(apiClientProvider)),
);

/// 首页 Banner 轮播，按展示位置取数：home_top 顶部 / home_middle 中部
/// （接口文档 2.7.13 的 position 入参；后端已按状态与展示时间窗过滤）。
final bannersProvider = FutureProvider.autoDispose.family<List<BannerItem>, String>(
  (ref, position) => ref.watch(contentRepositoryProvider).listBanners(position: position),
);

/// 标签（作品列表的标签筛选项）。
///
/// 标签墙体系下作品只按标签归属，筛选项直接取全量启用标签。
final tagsProvider = FutureProvider.autoDispose<List<TagItem>>(
  (ref) => ref.watch(contentRepositoryProvider).listTags(),
);

/// 分类页导航：频道 + 热门标签 / 主题 / 角色 / 情节四维度分组。
///
/// 入参为频道ID；null 时由后端回落第一个频道。
final categoryNavProvider =
    FutureProvider.autoDispose.family<CategoryNav, int?>(
  (ref, channelId) =>
      ref.watch(contentRepositoryProvider).categoryNav(channelId: channelId),
);

/// 榜单：首页预览与榜单页共用；type 取 view/favorite/sale/rating/new，
/// 返回载荷含 list 与 updatedAt（榜单更新时间）。
final rankingProvider = FutureProvider.autoDispose.family<RankingPayload, String>(
  (ref, type) => ref.watch(contentRepositoryProvider).listRankings(type: type, limit: 20),
);

/// 首页热门精选：按「首页热门」坑位取数（recommendStatus=home_hot）。
///
/// 后端按坑位配置（1~20）合成：付费投放占对应位次、空位按浏览量自然补位，
/// 返回的就是完整坑位列表；首页只渲染前 6 本，点"更多"进入推荐列表页。
final hotWorksProvider = FutureProvider.autoDispose<List<BookItem>>(
  (ref) async {
    final repo = ref.watch(contentRepositoryProvider);
    final page = await repo.pageWorks(
      pageNum: 1,
      pageSize: 20,
      recommendStatus: 'home_hot',
    );
    return page.list;
  },
);

/// 搜索页推荐：按「搜索」坑位（共 5 个）合成，付费投放占位、空位自然补位，
/// 最多返回 5 本。
final searchRecommendProvider = FutureProvider.autoDispose<List<BookItem>>(
  (ref) async {
    final page = await ref
        .watch(contentRepositoryProvider)
        .pageWorks(pageNum: 1, pageSize: 5, showScope: 'search');
    return page.list;
  },
);

/// 作品详情；未上架/不存在时后端按 404 拒绝，页面展示错误态。
final workDetailProvider = FutureProvider.autoDispose.family<BookItem, int>(
  (ref, workId) => ref.watch(contentRepositoryProvider).workDetail(workId),
);

/// 版权合作联系方式；无档案时 hasContact=false，展示范围为空。
final workContactProvider = FutureProvider.autoDispose.family<WorkContact, int>(
  (ref, workId) => ref.watch(contentRepositoryProvider).workContact(workId),
);

/// 我的书架首屏（受保护内容，仅在守卫放行后拉取）。
///
/// 书架页的分页由页面内的 PagedListController 驱动（接口 2.7.12 返回真实分页），
/// 本 provider 供个人中心书架预览区块读取首屏数据（仅含已购 / 已授权作品）。
final shelfProvider = FutureProvider.autoDispose<ShelfPayload>(
  (ref) => ref.watch(contentRepositoryProvider).shelf(pageNum: 1, pageSize: 6),
);

/// 作品授权态（需 App Token，接口 2.7.12）。
///
/// 书架已改为「已购 / 已授权作品」派生，详情页不再提供加入书架动作，
/// 仅用本 provider 回显「已获授权 · 可读全文」或「试读」。
/// 游客不 watch（授权态必然为否），避免为必然 401 的请求往返。
final authorizedProvider = FutureProvider.autoDispose.family<bool, int>(
  (ref, workId) => ref.watch(contentRepositoryProvider).isWorkAuthorized(workId),
);

/// 搜索历史（需 App Token）。
///
/// autoDispose：搜索页进入后拉取；游客不 watch（历史区块隐藏），
/// 页面退出自动释放，不残留过期数据。
final searchHistoryProvider = FutureProvider.autoDispose<List<SearchHistoryItem>>(
  (ref) => ref.watch(contentRepositoryProvider).listSearchHistory(),
);

/// 作品收藏态（需 App Token，接口 2.7.10）。
///
/// 详情页是公开页，游客不 watch（收藏按钮点击时由 AuthGuard 引导登录），
/// 避免为必然 401 的请求往返。
final favoriteStatusProvider = FutureProvider.autoDispose.family<FavoriteState, int>(
  (ref, workId) => ref.watch(contentRepositoryProvider).favoriteStatus(workId),
);

/// 作品读者评分态（需 App Token）。
///
/// 详情页是公开页，游客不 watch（评分星星点击时由 AuthGuard 引导登录），
/// 避免为必然 401 的请求往返。
final workRatingProvider = FutureProvider.autoDispose.family<WorkRating, int>(
  (ref, workId) => ref.watch(contentRepositoryProvider).workRating(workId),
);

/// 作品章节目录；payload 含试读配置，每条章节自带 readable 标记。
final chapterListProvider = FutureProvider.autoDispose.family<ChapterListPayload, int>(
  (ref, workId) => ref.watch(contentRepositoryProvider).listChapters(workId),
);

/// 章节正文；超出试读范围时抛 [ApiException]（code=403），阅读页据此展示提示。
final chapterDetailProvider = FutureProvider.autoDispose.family<ChapterDetail, int>(
  (ref, chapterId) => ref.watch(contentRepositoryProvider).chapterDetail(chapterId),
);


/// 指定作者的上架作品（个人主页「TA 的作品」）。
final authorWorksProvider =
    FutureProvider.autoDispose.family<PagedData<BookItem>, int>(
  (ref, authorId) => ref.watch(contentRepositoryProvider).pageWorks(
        authorId: authorId,
        pageNum: 1,
        pageSize: 30,
      ),
);
