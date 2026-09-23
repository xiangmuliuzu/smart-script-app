import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_providers.dart';
import 'content_repository.dart';

/// A6 示例业务模块依赖注入（与框架层同源，不新建网络栈）。

final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepository(ref.watch(apiClientProvider)),
);

/// 公开作品列表：游客也可读取，进入书城时拉取。
///
/// 订阅登录态：公开接口对已登录用户返回个性化摘要，若不在登录态变化时重新拉取，
/// 用户在书城停留期间登录后会继续看到游客视角的摘要（接口本身允许匿名，
/// 因此这属于客户端刷新问题）。`.select(status)` 只在登录态真正变化时触发重取。
final worksProvider = FutureProvider.autoDispose<WorksPayload>((ref) {
  ref.watch(authControllerProvider.select((state) => state.status));
  return ref.watch(contentRepositoryProvider).listWorks();
});

/// 我的书架：受保护内容，仅在守卫放行后拉取。
final shelfProvider = FutureProvider.autoDispose<ShelfPayload>(
  (ref) => ref.watch(contentRepositoryProvider).shelf(),
);
