import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../user_center/data/paged_data.dart';
import 'create_models.dart';
import 'create_repository.dart';

/// B 模块「上传与创作」依赖注入（复用框架层网络栈，不新建 Dio）。

final createRepositoryProvider = Provider<CreateRepository>(
  (ref) => CreateRepository(ref.watch(apiClientProvider)),
);

/// 作品审核状态（接口 2.9.6）。
final reviewStatusProvider = FutureProvider.autoDispose.family<ReviewStatus, int>(
  (ref, workId) => ref.watch(createRepositoryProvider).reviewStatus(workId),
);

/// 作品版本列表（接口 2.9.7）；新建版本后页面调用 `ref.invalidate` 刷新。
final workVersionsProvider = FutureProvider.autoDispose.family<List<WorkVersionItem>, int>(
  (ref, workId) => ref.watch(createRepositoryProvider).listVersions(workId),
);

/// 单版本详情（接口 2.9.9，含 content 全文）。
final workVersionDetailProvider =
    FutureProvider.autoDispose.family<WorkVersionDetail, int>(
  (ref, versionId) => ref.watch(createRepositoryProvider).versionDetail(versionId),
);

/// 我的草稿箱分页（接口 2.9.5）；key 为页码（从 1 开始），每页 10 条。
final draftListProvider = FutureProvider.autoDispose.family<PagedData<DraftWorkItem>, int>(
  (ref, pageNum) =>
      ref.watch(createRepositoryProvider).pageDrafts(pageNum: pageNum, pageSize: 10),
);

/// 作者视角章节列表（章节管理用）；增删改后页面调用 `ref.invalidate` 刷新。
final authorChapterListProvider =
    FutureProvider.autoDispose.family<List<AuthorChapterItem>, int>(
  (ref, workId) => ref.watch(createRepositoryProvider).listWorkChapters(workId),
);