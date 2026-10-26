import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/income_models.dart';
import '../data/income_providers.dart';

/// 我的收益 · 总览页。
class MyIncomeOverviewPage extends ConsumerWidget {
  const MyIncomeOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(myIncomeOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收益'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myIncomeOverviewProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              overview.when(
                data: (data) => _OverviewCard(
                  data: data,
                  onWithdraw: () => context.push(RoutePath.myIncomeWithdraw),
                ),
                loading: () => _OverviewCard(
                  data: const IncomeOverview(
                    totalIncome: 0,
                    pendingSettleAmount: 0,
                    availableAmount: 0,
                  ),
                  loading: true,
                  onWithdraw: () => context.push(RoutePath.myIncomeWithdraw),
                ),
                error: (e, _) => _ErrorBox(
                  message: '加载失败：$e',
                  onRetry: () => ref.invalidate(myIncomeOverviewProvider),
                ),
              ),
              const SizedBox(height: 16),
              overview.maybeWhen(
                data: (data) => _SubEntryCard(
                  icon: Icons.pending_actions_outlined,
                  title: '待结算',
                  subtitle: '确认无误后收益才会到账',
                  color: Colors.orange,
                  badgeCount: data.pendingSettleCount,
                  onTap: () => context.push(RoutePath.myIncomeSettleList),
                ),
                orElse: () => _SubEntryCard(
                  icon: Icons.pending_actions_outlined,
                  title: '待结算',
                  subtitle: '确认无误后收益才会到账',
                  color: Colors.orange,
                  onTap: () => context.push(RoutePath.myIncomeSettleList),
                ),
              ),
              const SizedBox(height: 12),
              _SubEntryCard(
                icon: Icons.receipt_long_outlined,
                title: '收益明细',
                subtitle: '已到账记录，点击查看详情',
                color: AppColors.primary,
                onTap: () => context.push(RoutePath.myIncomeDetail),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.data,
    required this.onWithdraw,
    this.loading = false,
  });

  final IncomeOverview data;
  final VoidCallback onWithdraw;
  final bool loading;

  String _fmt(double v) => loading ? '...' : '¥${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(
                  label: '总收益',
                  value: _fmt(data.totalIncome),
                  large: true,
                ),
              ),
              Material(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: onWithdraw,
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          '提现',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 28),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: '待结算收益',
                  value: _fmt(data.pendingSettleAmount),
                  compact: true,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: '可提现收益',
                  value: _fmt(data.availableAmount),
                  compact: true,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: '已提现收益',
                  value: _fmt(data.withdrawnAmount),
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.large = false,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: compact ? 11 : 13,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: large ? 28 : (compact ? 15 : 20),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _SubEntryCard extends StatelessWidget {
  const _SubEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
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
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: AppColors.text3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(message, style: const TextStyle(color: AppColors.text2)),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
