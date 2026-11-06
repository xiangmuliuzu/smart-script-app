import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'demand_repository.dart';
import 'trade_models.dart';

/// 任务广场 Providers。
///
/// 列表分页不再走 FutureProvider.family（已改由 [DemandPager] 状态机承载，
/// 见 demand_pager.dart），避免整页缓存丢失累积列表。

final demandRepositoryProvider = Provider<DemandRepository>(
  (ref) => DemandRepository(ref.watch(apiClientProvider)),
);

// ==================== 详情 ====================

/// 任务详情
final demandDetailProvider = FutureProvider.autoDispose.family<DemandTask, int>(
  (ref, demandId) => ref.watch(demandRepositoryProvider).demandDetail(demandId),
);

// ==================== Hero 统计 ====================

/// Hero 横幅统计：可接单数 / 奖金池(分) / 今日新增 / 各题材待接单数（供 chip 角标）。
///
/// 走后端 `/trade/demand/stats` 轻量聚合接口（口径 open+escrowed），
/// 不再为拿 total 而发一次整表列表请求；金额与 /list 一致以分交互。
class DemandStats {
  final int openCount;
  final int prizePoolFen; // 奖金池（分）
  final int todayNewCount;
  final Map<int, int> genreCounts; // genreId → 待接单数（公开口径 open+escrowed）

  const DemandStats({
    this.openCount = 0,
    this.prizePoolFen = 0,
    this.todayNewCount = 0,
    this.genreCounts = const <int, int>{},
  });

  /// 奖金池（整元，供展示）。
  int get prizePoolYuan => (prizePoolFen / 100).round();

  factory DemandStats.fromMap(Map<String, dynamic> m) {
    final gc = <int, int>{};
    final rows = m['genreCounts'];
    if (rows is List) {
      for (final r in rows) {
        if (r is Map) {
          final gid = (r['genreId'] as num?)?.toInt();
          final cnt = (r['count'] as num?)?.toInt() ?? 0;
          if (gid != null) gc[gid] = cnt;
        }
      }
    }
    final open = (m['availableCount'] as num?)?.toInt() ?? 0;
    return DemandStats(
      openCount: open,
      prizePoolFen: (m['prizePoolFen'] as num?)?.toInt() ?? 0,
      todayNewCount: (m['todayNewCount'] as num?)?.toInt() ?? 0,
      genreCounts: gc,
    );
  }
}

final demandStatsProvider = FutureProvider.autoDispose<DemandStats>((ref) async {
  final map = await ref.watch(demandRepositoryProvider).demandStats();
  return DemandStats.fromMap(map);
});

// ==================== 验收轮次 ====================

/// 某任务的验收轮次列表
final demandStagesProvider = FutureProvider.autoDispose.family<List<DemandStage>, int>(
  (ref, demandId) => ref.watch(demandRepositoryProvider).demandStages(demandId),
);

/// 某任务的延时记录（申请延时 + 自主延时，每条动作一行，通过/驳回均保留；仅任务双方可查）
final demandExtendHistoryProvider =
    FutureProvider.autoDispose.family<List<DemandExtendApply>, int>(
  (ref, demandId) => ref.watch(demandRepositoryProvider).extendHistory(demandId),
);
