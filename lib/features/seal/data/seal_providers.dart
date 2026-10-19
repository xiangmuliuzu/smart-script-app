import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'seal_models.dart';
import 'seal_repository.dart';

/// 印章仓库 Provider。
final sealRepositoryProvider = Provider<SealRepository>(
  (ref) => SealRepository(ref.watch(apiClientProvider)),
);

/// 我的印章列表 Provider。
final mySealsProvider = FutureProvider<List<SealItem>>((ref) async {
  final repo = ref.watch(sealRepositoryProvider);
  return repo.mySeals();
});

/// 印章详情 Provider（需要 sealId 参数）。
final sealDetailProvider = FutureProvider.family<SealDetail?, int>((ref, sealId) async {
  final repo = ref.watch(sealRepositoryProvider);
  return repo.sealDetail(sealId);
});
