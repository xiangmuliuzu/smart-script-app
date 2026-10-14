import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import 'data/welfare_models.dart';
import 'data/welfare_providers.dart';

/// 积分明细页（App 端 E 模块）。
class WelfarePointsDetailPage extends ConsumerWidget {
  const WelfarePointsDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(pointsRecordsProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('积分明细'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pointsRecordsProvider.future),
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

  final PointsRecord record;

  String get _sourceLabel {
    switch (record.source) {
      case 'TASK':
        return '任务奖励';
      case 'AD':
        return '广告奖励';
      case 'EXCHANGE':
        return '积分兑换';
      case 'SIGN':
        return '签到';
      default:
        return record.source.isEmpty ? '积分变动' : record.source;
    }
  }

  @override
  Widget build(BuildContext context) {
    final positive = record.points >= 0;
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
              color: positive ? AppColors.primaryTint : AppColors.fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              positive ? Icons.add_circle_outline : Icons.remove_circle_outline,
              color: positive ? AppColors.primary : AppColors.text3,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.remark.isEmpty ? _sourceLabel : record.remark,
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
                record.signedPoints,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: positive ? AppColors.success : AppColors.danger,
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
          Icon(Icons.receipt_long_outlined,
              size: 48, color: AppColors.text3),
          SizedBox(height: 12),
          Text('暂无积分明细', style: TextStyle(color: AppColors.text3)),
        ],
      ),
    );
  }
}
