import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'create_models.dart';
import 'create_repository.dart';

/// B 模块创作（上传 / 版本）依赖注入（复用框架层网络栈，不新建 Dio）。
///
/// 「我的作品」写作链路的 Provider 见 `author_work_providers.dart`。

final createRepositoryProvider = Provider<CreateRepository>(
  (ref) => CreateRepository(ref.watch(apiClientProvider)),
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