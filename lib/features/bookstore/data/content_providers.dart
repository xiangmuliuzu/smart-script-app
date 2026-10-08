import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'bookstore_models.dart';
import 'content_repository.dart';

/// B 模块书城依赖注入（复用框架层网络栈，不新建 Dio）。

final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepository(ref.watch(apiClientProvider)),
);

/// 首页 Banner 轮播；不传 position，后端已按状态与展示时间窗过滤。
final bannersProvider = FutureProvider.autoDispose<List<BannerItem>>(
  (ref) => ref.watch(contentRepositoryProvider).listBanners(),
);

/// 顶级分类（书城分类入口）。parent_id=0 与后端新增分类的默认值一致。
final categoriesProvider = FutureProvider.autoDispose<List<CategoryItem>>(
  (ref) => ref.watch(contentRepositoryProvider).listCategories(parentId: 0),
);

/// 标签（作品列表的标签筛选项）。
final tagsProvider = FutureProvider.autoDispose<List<TagItem>>(
  (ref) => ref.watch(contentRepositoryProvider).listTags(),
);

/// 榜单：首页预览与榜单页共用；type 取 view/favorite/sale/rating。
final rankingProvider = FutureProvider.autoDispose.family<List<RankingItem>, String>(
  (ref, type) => ref.watch(contentRepositoryProvider).listRankings(type: type, limit: 20),
);

/// 首页推荐流（最新上架前 6 部）。
final recommendedWorksProvider = FutureProvider.autoDispose<List<BookItem>>(
  (ref) async {
    final page = await ref
        .watch(contentRepositoryProvider)
        .pageWorks(pageNum: 1, pageSize: 6, sort: 'latest');
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

/// 我的书架：受保护内容，仅在守卫放行后拉取。
final shelfProvider = FutureProvider.autoDispose<ShelfPayload>(
  (ref) => ref.watch(contentRepositoryProvider).shelf(),
);

/// 搜索历史（需 App Token）。
///
/// autoDispose：搜索页进入后拉取；游客不 watch（历史区块隐藏），
/// 页面退出自动释放，不残留过期数据。
final searchHistoryProvider = FutureProvider.autoDispose<List<SearchHistoryItem>>(
  (ref) => ref.watch(contentRepositoryProvider).listSearchHistory(),
);

/// 作品章节目录；payload 含试读配置，每条章节自带 readable 标记。
final chapterListProvider = FutureProvider.autoDispose.family<ChapterListPayload, int>(
  (ref, workId) => ref.watch(contentRepositoryProvider).listChapters(workId),
);

/// 章节正文；超出试读范围时抛 [ApiException]（code=403），阅读页据此展示提示。
final chapterDetailProvider = FutureProvider.autoDispose.family<ChapterDetail, int>(
  (ref, chapterId) => ref.watch(contentRepositoryProvider).chapterDetail(chapterId),
);

