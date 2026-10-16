import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 资金托管记录页
///
/// 顶部概览（托管总额/待释放）+ 状态筛选 + 托管列表。
class EscrowListPage extends ConsumerStatefulWidget {
  const EscrowListPage({super.key});

  @override
  ConsumerState<EscrowListPage> createState() => _EscrowListPageState();
}

class _EscrowListPageState extends ConsumerState<EscrowListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentRole => _tabController.index == 0 ? 'buyer' : 'seller';

  @override
  Widget build(BuildContext context) {
    final escrows = ref.watch(
      escrowSummaryProvider(EscrowListParams(role: _currentRole, status: _statusFilter)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('资金托管记录'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [Tab(text: '买方视角'), Tab(text: '卖方视角')],
          onTap: (_) {
            setState(() => _statusFilter = null);
          },
        ),
      ),
      body: Container(
        color: Colors.grey[100],
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(escrowSummaryProvider(
              EscrowListParams(role: _currentRole, status: _statusFilter),
            ));
          },
          child: escrows.when(
            data: (summary) => _buildContent(summary),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(EscrowSummary summary) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(summary.totalAmount, summary.pendingAmount),
        const SizedBox(height: 12),
        _buildStatusFilter(),
        const SizedBox(height: 12),
        if (summary.list.isEmpty)
          const _EmptyHint()
        else
          ...summary.list.map((e) => _EscrowCard(escrow: e)),
      ],
    );
  }

  Widget _buildSummaryCard(int total, int pending) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue, Colors.blue.withOpacity(0.7)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryItem(label: '托管总额', value: '¥${(total / 100).toStringAsFixed(2)}'),
          Container(width: 1, height: 30, color: Colors.white24),
          _SummaryItem(label: '待释放', value: '¥${(pending / 100).toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    const filters = <String?>[null, 'pending', 'escrowed', 'released', 'refunded'];
    const labels = ['全部', '待托管', '托管中', '已释放', '已退款'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(filters.length, (i) {
          final selected = _statusFilter == filters[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[i]),
              selected: selected,
              selectedColor: Colors.blue.withOpacity(0.2),
              onSelected: (_) {
                setState(() => _statusFilter = filters[i]);
              },
            ),
          );
        }),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  const _SummaryItem({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
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

class _EscrowCard extends StatelessWidget {
  final Escrow escrow;
  const _EscrowCard({required this.escrow});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(escrow.status);
    final statusLabel = EscrowStatus.label(escrow.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(escrow.escrowNo ?? '-', style: const TextStyle(
                  fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500,
                )),
                Text(escrow.amountYuan, style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                )),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [escrow.orderNo, escrow.workTitle].where((s) => s != null && s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '买方: ${escrow.buyerName ?? "-"}  卖方: ${escrow.sellerName ?? "-"}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12)),
                ),
                Text(formatDate(escrow.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'escrowed': return Colors.blue;
      case 'released': return Colors.green;
      case 'refunded': return Colors.red;
      default: return Colors.grey;
    }
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('暂无托管记录', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}
