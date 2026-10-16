import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../user_center/data/paged_data.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 作者收益页
///
/// 顶部概览卡片（累计/本月/可提现/冻结）+ 作品收益排行 + 收益明细列表。
class IncomeOverviewPage extends ConsumerStatefulWidget {
  const IncomeOverviewPage({super.key});

  @override
  ConsumerState<IncomeOverviewPage> createState() => _IncomeOverviewPageState();
}

class _IncomeOverviewPageState extends ConsumerState<IncomeOverviewPage> {
  String? _billTypeFilter;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(incomeOverviewProvider);
    final billRecords = ref.watch(
      billRecordListProvider(BillRecordListParams(billType: _billTypeFilter)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('作者收益'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[100],
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(incomeOverviewProvider);
            ref.invalidate(billRecordListProvider(
              BillRecordListParams(billType: _billTypeFilter),
            ));
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildOverviewCard(overview),
              const SizedBox(height: 16),
              _buildBillTypeFilter(),
              const SizedBox(height: 12),
              _buildBillRecordList(billRecords),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(AsyncValue<Map<String, dynamic>> overview) {
    return overview.when(
      data: (data) {
        final totalIncome = _formatYuan(data['totalIncome']);
        final monthIncome = _formatYuan(data['monthIncome']);
        final available = _formatYuan(data['availableAmount']);
        final frozen = _formatYuan(data['frozenAmount']);
        return _OverviewCard(
          totalIncome: totalIncome,
          monthIncome: monthIncome,
          available: available,
          frozen: frozen,
        );
      },
      loading: () => const _OverviewCard(
        totalIncome: '...', monthIncome: '...',
        available: '...', frozen: '...',
      ),
      error: (e, _) => _OverviewCard(
        totalIncome: '--', monthIncome: '--',
        available: '--', frozen: '--',
      ),
    );
  }

  Widget _buildBillTypeFilter() {
    const filters = <String?>[null, 'income', 'withdraw', 'settle'];
    const labels = ['全部', '收入', '提现', '结算'];
    return Row(
      children: List.generate(filters.length, (i) {
        final selected = _billTypeFilter == filters[i];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(labels[i]),
            selected: selected,
            selectedColor: AppColors.primary.withOpacity(0.2),
            onSelected: (_) {
              setState(() => _billTypeFilter = filters[i]);
            },
          ),
        );
      }),
    );
  }

  Widget _buildBillRecordList(AsyncValue<PagedData<BillRecord>> asyncData) {
    return asyncData.when(
      data: (paged) {
        if (paged.list.isEmpty) {
          return const _EmptyHint(icon: Icons.receipt_long_outlined, text: '暂无收益明细');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('收益明细', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...paged.list.map((b) => _BillRecordItem(record: b)),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
    );
  }

  String _formatYuan(dynamic value) {
    if (value == null) return '¥0.00';
    final num v = value is int ? value : (value is num ? value : 0);
    return '¥${(v).toStringAsFixed(2)}';
  }
}

class _OverviewCard extends StatelessWidget {
  final String totalIncome, monthIncome, available, frozen;
  const _OverviewCard({required this.totalIncome, required this.monthIncome,
    required this.available, required this.frozen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(label: '累计收益', value: totalIncome),
              _StatItem(label: '本月收益', value: monthIncome),
            ],
          ),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(label: '可提现', value: available),
              _StatItem(label: '冻结金额', value: frozen),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label, value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(
          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold,
        )),
      ],
    );
  }
}

class _BillRecordItem extends StatelessWidget {
  final BillRecord record;
  const _BillRecordItem({required this.record});

  @override
  Widget build(BuildContext context) {
    final isIncome = (record.amount ?? 0) >= 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isIncome ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
          child: Icon(
            isIncome ? Icons.arrow_upward : Icons.arrow_downward,
            color: isIncome ? Colors.green : Colors.orange,
            size: 20,
          ),
        ),
        title: Text(record.typeLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          [record.workTitle, record.orderNo].where((s) => s != null && s.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(record.amountYuan, style: TextStyle(
              color: isIncome ? Colors.green : Colors.orange,
              fontWeight: FontWeight.bold,
            )),
            Text(formatDate(record.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}
