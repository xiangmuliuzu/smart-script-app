import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../ai/data/ai_providers.dart';
import 'welfare_models.dart';
import 'welfare_repository.dart';

final welfareRepositoryProvider = Provider<WelfareRepository>(
  (ref) => WelfareRepository(ref.watch(apiClientProvider)),
);

/// 福利任务列表（含进度）。
final welfareTasksProvider = FutureProvider<List<WelfareTask>>((ref) {
  final userId = currentUserId(ref);
  if (userId == 0) throw StateError('未登录');
  return ref.watch(welfareRepositoryProvider).tasks(userId);
});

/// 积分余额。
final pointsBalanceProvider = FutureProvider<PointsBalance>((ref) {
  final userId = currentUserId(ref);
  if (userId == 0) throw StateError('未登录');
  return ref.watch(welfareRepositoryProvider).pointsBalance(userId);
});

/// 积分明细。
final pointsRecordsProvider = FutureProvider<List<PointsRecord>>((ref) {
  final userId = currentUserId(ref);
  if (userId == 0) throw StateError('未登录');
  return ref.watch(welfareRepositoryProvider).pointsRecords(userId);
});

/// 广告任务列表。
final adListProvider = FutureProvider<List<AdTask>>((ref) {
  final userId = currentUserId(ref);
  if (userId == 0) throw StateError('未登录');
  return ref.watch(welfareRepositoryProvider).adList(userId);
});

/// 兑换记录。
final exchangeRecordsProvider = FutureProvider<List<ExchangeRecord>>((ref) {
  final userId = currentUserId(ref);
  if (userId == 0) throw StateError('未登录');
  return ref.watch(welfareRepositoryProvider).exchangeRecords(userId);
});

/// 福利中心资产汇总（积分 + AI 机会）。
final welfareAssetProvider =
    FutureProvider<({PointsBalance points, int aiAvailable})>((ref) async {
  final userId = currentUserId(ref);
  if (userId == 0) throw StateError('未登录');
  final repo = ref.watch(welfareRepositoryProvider);
  final aiRepo = ref.watch(aiRepositoryProvider);
  final points = await repo.pointsBalance(userId);
  final ai = await aiRepo.balance(userId);
  return (points: points, aiAvailable: ai.available);
});
