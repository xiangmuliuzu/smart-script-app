import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/income_models.dart';
import '../data/income_providers.dart';

/// 已到账收益账单详情：来源、订单关联、分成核算。
class MyIncomeBillDetailPage extends ConsumerWidget {
  const MyIncomeBillDetailPage({super.key, required this.billId});

  final int billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDetail = ref.watch(incomeBillDetailProvider(billId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('收益详情'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: asyncDetail.when(
          data: (d) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(incomeBillDetailProvider(billId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _AmountHeader(detail: d),
                const SizedBox(height: 12),
                _InfoCard(
                  title: '收益来源',
                  children: [
                    _kv('类型', d.incomeSource ?? d.billType ?? '-'),
                    _kv('流水号', d.billNo ?? '-'),
                    _kv('备注', d.remark?.isNotEmpty == true ? d.remark! : '-'),
                    _kv('入账时间', d.createdAt ?? '-'),
                    _kv('变动后余额', d.fenYuan(d.balanceAfter)),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  title: '订单关联',
                  children: d.hasOrder
                      ? [
                          _kv('订单号', d.orderNo!),
                          _kv('作品', d.workTitle ?? '-'),
                          _kv('订单状态', d.orderStatus ?? '-'),
                          _kv('付款时间', d.payTime ?? '-'),
                          _kv('完成时间', d.completeTime ?? '-'),
                        ]
                      : [
                          const Text('无关联订单', style: TextStyle(color: AppColors.text3)),
                        ],
                ),
                if (d.hasOrder) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: '分成核算',
                    children: [
                      _kv('订单总额', d.fenYuan(d.totalAmount)),
                      _kv('平台抽成', d.fenYuan(d.platformFee)),
                      _kv('抽成比例', d.splitRateLabel),
                      _kv('作者实得', d.fenYuan(d.sellerAmount ?? d.amount)),
                      const SizedBox(height: 8),
                      const Text(
                        '说明：平台按订单总额抽取 5%，作者实得 = 订单总额 − 平台抽成。入账金额为作者实得。',
                        style: TextStyle(fontSize: 12, color: AppColors.text3),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败：$e'),
                TextButton(
                  onPressed: () => ref.invalidate(incomeBillDetailProvider(billId)),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(k, style: const TextStyle(color: AppColors.text3, fontSize: 13)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: AppColors.text1, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({required this.detail});

  final IncomeBillDetail detail;

  @override
  Widget build(BuildContext context) {
    final amount = detail.amount ?? 0;
    final positive = amount >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Text(
            detail.incomeSource ?? '收益',
            style: const TextStyle(color: AppColors.text2, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '${positive ? '+' : ''}¥${(amount / 100).toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: positive ? const Color(0xFF52C41A) : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
