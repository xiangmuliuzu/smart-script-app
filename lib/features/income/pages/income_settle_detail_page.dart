import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../data/income_providers.dart';

/// 待结算详情：确认入账 / 提出异议。
class MyIncomeSettleDetailPage extends ConsumerStatefulWidget {
  const MyIncomeSettleDetailPage({super.key, required this.settleId});

  final int settleId;

  @override
  ConsumerState<MyIncomeSettleDetailPage> createState() =>
      _MyIncomeSettleDetailPageState();
}

class _MyIncomeSettleDetailPageState
    extends ConsumerState<MyIncomeSettleDetailPage> {
  bool _busy = false;

  Future<void> _confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认入账'),
        content: const Text('确认金额无误后，收益将进入可提现余额，并写入收益明细。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(incomeRepositoryProvider).confirmSettle(widget.settleId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已确认，收益已到账')),
      );
      ref.invalidate(settleDetailProvider(widget.settleId));
      ref.invalidate(myIncomeOverviewProvider);
      ref.invalidate(settleListProvider(const SettleListParams(status: 'pending')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dispute() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提出异议'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: '请说明异议原因（必填）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写异议原因')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(incomeRepositoryProvider).disputeSettle(widget.settleId, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交异议')),
      );
      ref.invalidate(settleDetailProvider(widget.settleId));
      ref.invalidate(myIncomeOverviewProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(settleDetailProvider(widget.settleId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('结算确认'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: asyncDetail.when(
          data: (d) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(d.statusLabel, style: const TextStyle(color: AppColors.text2)),
                    const SizedBox(height: 8),
                    Text(
                      d.sellerAmountYuan,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('作者应得（确认后到账）',
                        style: TextStyle(fontSize: 12, color: AppColors.text3)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card('订单与分成', [
                _kv('结算单号', d.settleNo ?? '-'),
                _kv('订单号', d.orderNo ?? '-'),
                _kv('作品', d.workTitle ?? '-'),
                _kv('订单总额', d.fenYuan(d.totalAmount)),
                _kv('平台费用', d.fenYuan(d.platformFee)),
                _kv('分成比例', d.splitRate == null ? '-' : '${d.splitRate}'),
                _kv('作者实得', d.fenYuan(d.sellerAmount)),
                _kv('创建时间', d.createdAt ?? '-'),
              ]),
              if (d.status == 'disputed' && d.disputeReason != null) ...[
                const SizedBox(height: 12),
                _card('异议信息', [
                  _kv('异议原因', d.disputeReason!),
                  _kv('异议时间', d.disputeTime ?? '-'),
                ]),
              ],
              if (d.status == 'confirmed') ...[
                const SizedBox(height: 12),
                _card('入账信息', [
                  _kv('确认时间', d.confirmTime ?? '-'),
                  _kv('关联账单', d.billId != null ? '#${d.billId}' : '-'),
                ]),
              ],
              const SizedBox(height: 24),
              if (d.canConfirm)
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(d.status == 'disputed' ? '异议已处理，确认入账' : '确认无误，收款到账'),
                  ),
                ),
              if (d.canDispute) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _dispute,
                    child: const Text('有异议'),
                  ),
                ),
              ],
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...children,
        ],
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
          Expanded(child: Text(v, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
