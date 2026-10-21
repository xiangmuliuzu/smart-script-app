import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_providers.dart';
import 'seal_models.dart';
import 'seal_repository.dart';

/// 印章仓库 Provider。
final sealRepositoryProvider = Provider<SealRepository>(
  (ref) => SealRepository(ref.watch(apiClientProvider)),
);

/// 我的印章列表。
///
/// 绑定当前登录 userId：退出 / 换号后自动失效重拉，避免继续展示上一个账号的缓存。
final mySealsProvider = FutureProvider.autoDispose<List<SealItem>>((ref) async {
  final userId = ref.watch(
    authControllerProvider.select((state) => state.user?.userId),
  );
  if (userId == null) return const [];

  final repo = ref.watch(sealRepositoryProvider);
  return repo.mySeals();
});

/// 印章详情（含材料、日志）。
///
/// 同样绑定登录 userId，并使用 autoDispose，避免把「404 → null」永久缓存在内存里，
/// 导致重新登录后仍显示「印章不存在或无权限访问」。
final sealDetailProvider =
    FutureProvider.autoDispose.family<SealDetail?, int>((ref, sealId) async {
  final userId = ref.watch(
    authControllerProvider.select((state) => state.user?.userId),
  );
  if (userId == null || sealId <= 0) return null;

  final repo = ref.watch(sealRepositoryProvider);
  return repo.sealDetail(sealId);
});
