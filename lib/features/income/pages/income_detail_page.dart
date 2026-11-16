import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/income_models.dart';
import '../data/income_providers.dart';

/// 我的收益 · 已到账明细列表（含周/月/年收支统计）。
class MyIncomeDetailPage extends ConsumerStatefulWidget {
  const MyIncomeDetailPage({super.key});

  @override
  ConsumerState<MyIncomeDetailPage> createState() => _MyIncomeDetailPageState();
}

class _MyIncomeDetailPageState extends ConsumerState<MyIncomeDetailPage> {
  String? _billType;
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final params = IncomeDetailParams(billType: _billType);
    final asyncData = ref.watch(incomeDetailListProvider(params));
    final asyncStats = ref.watch(incomeStatsProvider(_period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('收益明细'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(incomeDetailListProvider(params));
            ref.invalidate(incomeStatsProvider(_period));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _StatsCard(
                    period: _period,
                    stats: asyncStats,
                    onPeriodChanged: (p) => setState(() => _period = p),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _FilterChips(
                    selected: _billType,
                    onSelected: (v) => setState(() => _billType = v),
                  ),
                ),
              ),
              asyncData.when(
                data: (paged) {
                  if (paged.list.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: _EmptyHint(text: '暂无已到账收益记录'),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final item = paged.list[i];
                          return _DetailTile(
                            item: item,
                            onTap: () {
                              if (item.billId == null) return;
                              context.push(
                                RoutePath.myIncomeBillDetailUrl(item.billId!),
                              );
                            },
                          );
                        },
                        childCount: paged.list.length,
                      ),
                    ),
                  );
                },
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text('加载失败：$e'),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(incomeDetailListProvider(params)),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.period,
    required this.stats,
    required this.onPeriodChanged,
  });

  final String period;
  final AsyncValue<IncomePeriodStats> stats;
  final ValueChanged<String> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '收入提现统计',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: period,
                  isDense: true,
                  style: const TextStyle(fontSize: 14, color: AppColors.text1),
                  items: const [
                    DropdownMenuItem(value: 'week', child: Text('按周')),
                    DropdownMenuItem(value: 'month', child: Text('按月')),
                    DropdownMenuItem(value: 'year', child: Text('按年')),
                  ],
                  onChanged: (v) {
                    if (v != null) onPeriodChanged(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          stats.when(
            data: (s) => Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: '收入合计',
                    value: '¥${s.incomeAmount.toStringAsFixed(2)}',
                    color: const Color(0xFF52C41A),
                  ),
                ),
                Expanded(
                  child: _StatCell(
                    label: '提现合计',
                    value: '¥${s.withdrawAmount.toStringAsFixed(2)}',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text('统计加载失败：$e',
                style: const TextStyle(color: AppColors.text3, fontSize: 12)),
          ),
          if (stats.hasValue && stats.value!.periodStart != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '统计区间：${stats.value!.periodStart} ~ ${stats.value!.periodEnd}',
                style: const TextStyle(fontSize: 11, color: AppColors.text3),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = <String?>[null, 'income', 'withdraw'];
    const labels = ['全部', '收入', '提现'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(filters.length, (i) {
          final selectedChip = selected == filters[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[i]),
              selected: selectedChip,
              selectedColor: AppColors.primary.withOpacity(0.15),
              onSelected: (_) => onSelected(filters[i]),
            ),
          );
        }),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.item, required this.onTap});

  final IncomeDetailItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isIncome = (item.amount ?? 0) >= 0;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.sourceLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.orderSummary,
                      style: const TextStyle(fontSize: 13, color: AppColors.text2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmtDate(item.createdAt),
                      style: const TextStyle(fontSize: 12, color: AppColors.text3),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.amountYuan,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isIncome ? const Color(0xFF52C41A) : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right, color: AppColors.text3, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }
}
