import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'author_work_models.dart';
import 'author_work_repository.dart';

/// B 模块「我的作品」写作链路依赖注入（A 套 /users/me/works，复用框架层网络栈）。

final authorWorkRepositoryProvider = Provider<AuthorWorkRepository>(
  (ref) => AuthorWorkRepository(ref.watch(apiClientProvider)),
);

/// 我的作品列表；key 为状态筛选（all / draft / reviewing / revision / rejected / published）。
///
/// 列表不分页，服务端按审核派生状态过滤；创建 / 保存 / 提交后由页面 invalidate 刷新。
final myWorksProvider =
    FutureProvider.autoDispose.family<List<AuthorWorkItem>, String>(
  (ref, status) => ref.watch(authorWorkRepositoryProvider).listWorks(status: status),
);

/// 作品工作台详情（单一数据源：作品 + 章节 + 最近审核）。
///
/// 设置 Tab 保存、章节增删改后由页面 `ref.invalidate(authorWorkDetailProvider(workId))`
/// 刷新，保证顶部作品卡与各 Tab 数据一致。
final authorWorkDetailProvider =
    FutureProvider.autoDispose.family<AuthorWorkDetail, int>(
  (ref, workId) => ref.watch(authorWorkRepositoryProvider).workDetail(workId),
);

/// 审核记录列表（审核历史 + 管理员意见）。
final authorReviewRecordsProvider =
    FutureProvider.autoDispose.family<List<ReviewRecordItem>, int>(
  (ref, workId) => ref.watch(authorWorkRepositoryProvider).reviewRecords(workId),
);