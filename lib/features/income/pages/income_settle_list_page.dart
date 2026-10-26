import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/income_models.dart';
import '../data/income_providers.dart';

/// 待结算列表（到账前确认/异议）。
class MyIncomeSettleListPage extends ConsumerStatefulWidget {
  const MyIncomeSettleListPage({super.key});

  @override
  ConsumerState<MyIncomeSettleListPage> createState() =>
      _MyIncomeSettleListPageState();
}

class _MyIncomeSettleListPageState extends ConsumerState<MyIncomeSettleListPage> {
  String? _status = 'pending';

  @override
  Widget build(BuildContext context) {
    final params = SettleListParams(status: _status);
    final asyncData = ref.watch(settleListProvider(params));

    return Scaffold(
      appBar: AppBar(
        title: const Text('待结算'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e in <(String?, String)>[
                      ('pending', '待确认'),
                      ('disputed', '有异议'),
                      ('confirmed', '已入账'),
                      (null, '全部'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.$2),
                          selected: _status == e.$1,
                          selectedColor: AppColors.primary.withOpacity(0.15),
                          onSelected: (_) => setState(() => _status = e.$1),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(settleListProvider(params));
                  ref.invalidate(myIncomeOverviewProvider);
                },
                child: asyncData.when(
                  data: (paged) {
                    if (paged.list.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text('暂无记录', style: TextStyle(color: AppColors.text3)),
                          ),
                        ],
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: paged.list.length,
                      itemBuilder: (_, i) {
                        final item = paged.list[i];
                        return _SettleTile(
                          item: item,
                          onTap: () {
                            if (item.settleId == null) return;
                            context.push(
                              RoutePath.myIncomeSettleDetailUrl(item.settleId!),
                            );
                          },
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败：$e')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettleTile extends StatelessWidget {
  const _SettleTile({required this.item, required this.onTap});

  final IncomeSettleItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final needAction = item.status == 'pending';
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (needAction)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.workTitle?.isNotEmpty == true
                          ? item.workTitle!
                          : (item.orderNo ?? item.settleNo ?? '结算单'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.orderNo ?? '-'} · ${item.statusLabel}',
                      style: const TextStyle(fontSize: 13, color: AppColors.text2),
                    ),
                    if (item.createdAt != null)
                      Text(
                        item.createdAt!,
                        style: const TextStyle(fontSize: 12, color: AppColors.text3),
                      ),
                  ],
                ),
              ),
              Text(
                item.sellerAmountYuan,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}
