import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'content_repository.dart';

/// A6 示例业务模块依赖注入（与框架层同源，不新建网络栈）。

final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepository(ref.watch(apiClientProvider)),
);

/// 公开作品列表：游客也可读取，进入书城时拉取。
final worksProvider = FutureProvider.autoDispose<WorksPayload>(
  (ref) => ref.watch(contentRepositoryProvider).listWorks(),
);

/// 我的书架：受保护内容，仅在守卫放行后拉取。
final shelfProvider = FutureProvider.autoDispose<ShelfPayload>(
  (ref) => ref.watch(contentRepositoryProvider).shelf(),
);
