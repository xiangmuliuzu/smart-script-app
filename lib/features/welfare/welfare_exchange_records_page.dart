import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import 'data/welfare_models.dart';
import 'data/welfare_providers.dart';

/// 兑换记录页（App 端 E 模块）：积分 → AI 机会的兑换流水。
class WelfareExchangeRecordsPage extends ConsumerWidget {
  const WelfareExchangeRecordsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(exchangeRecordsProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('兑换记录'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(exchangeRecordsProvider.future),
        child: records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('加载失败，下拉重试')),
          data: (list) {
            if (list.isEmpty) {
              return const _Empty();
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _RecordTile(record: list[index]),
            );
          },
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final ExchangeRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.cyanTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.swap_horiz,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.remark.isEmpty
                      ? '积分兑换 AI 机会'
                      : record.remark,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text1),
                ),
                const SizedBox(height: 2),
                Text(
                  record.createTime ?? '',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${record.spentPoints} 积分',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 2),
              Text('余额 ${record.balanceAfter}',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.text3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 48, color: AppColors.text3),
          SizedBox(height: 12),
          Text('暂无兑换记录', style: TextStyle(color: AppColors.text3)),
        ],
      ),
    );
  }
}
