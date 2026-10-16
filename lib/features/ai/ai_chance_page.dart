import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import 'data/ai_models.dart';
import 'data/ai_providers.dart';

/// AI 机会页（E 模块）：机会余额、累计获得/消耗/补偿、兑换比例与最近流水。
///
/// 数据源 GET /api/v1/ai/quota/balance（aiBalanceProvider）；
/// 顶部「去兑换」跳福利中心兑换页；支持下拉/右上角刷新。
class AiChancePage extends ConsumerWidget {
  const AiChancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aiBalanceProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('AI 机会'),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => ref.invalidate(aiBalanceProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(aiBalanceProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: '机会数据加载失败',
            onRetry: () => ref.invalidate(aiBalanceProvider),
          ),
          data: (balance) => _Content(balance: balance),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.balance});

  final AiQuotaBalance balance;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        _BalanceCard(balance: balance),
        const SizedBox(height: 12),
        _StatsCard(balance: balance),
        const SizedBox(height: 12),
        _RecordsCard(records: balance.records),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 顶部渐变卡：可用次数 + 兑换比例 + 去兑换。
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final AiQuotaBalance balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('可用 AI 机会',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${balance.available}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      height: 1)),
              const Padding(
                padding: EdgeInsets.only(bottom: 6, left: 6),
                child: Text('次',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${balance.rate} 积分 = 1 次，只能积分换次数',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => context.push(RoutePath.welfareExchange),
                child: const Text('去兑换',
                    style: TextStyle(
                        color: AppColors.primary, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 累计统计卡（获得 / 消耗 / 补偿）。
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.balance});

  final AiQuotaBalance balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
      ),
      child: Row(
        children: [
          _Stat(label: '累计获得', value: balance.totalEarned),
          _divider(),
          _Stat(label: '累计消耗', value: balance.totalConsumed),
          _divider(),
          _Stat(label: '累计补偿', value: balance.totalRefunded),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 28, color: AppColors.divider);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$value',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text1)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.text3)),
        ],
      ),
    );
  }
}

/// 最近流水卡。
class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.records});

  final List<AiQuotaRecord> records;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text('机会明细（最近 10 条）',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text1)),
          ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('暂无流水记录',
                  style: TextStyle(fontSize: 13, color: AppColors.text3)),
            )
          else
            ...records.map((r) => _RecordTile(record: r)),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final AiQuotaRecord record;

  @override
  Widget build(BuildContext context) {
    final Color color = record.isOutgoing ? AppColors.text2 : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.typeLabel,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text1)),
                const SizedBox(height: 4),
                Text(record.createTime ?? '',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.text3)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(record.signedAmount,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 4),
              Text('余额 ${record.balanceAfter}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.text3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              Text(message,
                  style: const TextStyle(
                      color: AppColors.text3, fontSize: 14)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ],
    );
  }
}
