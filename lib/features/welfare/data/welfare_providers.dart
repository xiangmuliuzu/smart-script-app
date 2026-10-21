import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_providers.dart';
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

/// 上报指定类型任务的行为进度（真实行为埋点，如登录/上传/阅读）。
/// fire-and-forget：任何失败静默，不打断主流程；只对启用且未领取的任务上报。
/// [ref] 可以是 Provider 内 [Ref] 或 Widget 内 [WidgetRef]（均支持 read/invalidate）。
Future<void> reportTaskProgressByType(dynamic ref, String taskType,
    {int increment = 1}) async {
  try {
    final authState = ref.read(authControllerProvider) as AuthState;
    final userId = authState.user?.userId ?? 0;
    if (userId == 0) return;
    final tasks =
        await (ref.read(welfareTasksProvider.future) as Future<List<WelfareTask>>);
    final target = tasks.firstWhere(
      (t) => t.taskType == taskType && t.isClaimed != 1,
      orElse: () => tasks.isEmpty
          ? _emptyTask(taskType)
          : tasks.firstWhere((t) => t.taskType == taskType,
              orElse: () => _emptyTask(taskType)),
    );
    if (target.taskCode.isEmpty) return;
    await ref.read(welfareRepositoryProvider).reportTaskProgress(
          userId: userId,
          taskCode: target.taskCode,
          increment: increment,
        );
    // 上报成功后有进度变化，刷新任务列表供福利页展示
    ref.invalidate(welfareTasksProvider);
  } catch (_) {
    // 静默：未登录/网络失败/任务不存在都不影响主流程。
  }
}

WelfareTask _emptyTask(String taskType) => WelfareTask(
      taskId: 0,
      taskName: '',
      taskType: taskType,
      taskCode: '',
      description: '',
      targetCount: 1,
      rewardPoints: 0,
      icon: '',
      progress: 0,
      isCompleted: 0,
      isClaimed: 0,
      periodDate: null,
    );
