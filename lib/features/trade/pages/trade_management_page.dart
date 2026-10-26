import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';

/// 交易管理页
///
/// 包含 6 个功能入口：询盘管理、交易会话、订单管理、资金托管记录、我的收益、发票申请。
class TradeManagementPage extends StatelessWidget {
  const TradeManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('交易管理'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[100],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildMenuRow([
                      _MenuItem(
                        icon: Icons.headset_mic_outlined,
                        label: '询盘管理',
                        color: Colors.purple,
                        onTap: () => context.push(RoutePath.inquiryList),
                      ),
                      _MenuItem(
                        icon: Icons.chat_outlined,
                        label: '交易会话',
                        color: Colors.indigo,
                        onTap: () => context.push(RoutePath.tradeSessionList),
                      ),
                      _MenuItem(
                        icon: Icons.shopping_bag_outlined,
                        label: '订单管理',
                        color: Colors.teal,
                        onTap: () => context.push(RoutePath.orderList),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    _buildMenuRow([
                      _MenuItem(
                        icon: Icons.account_balance_wallet_outlined,
                        label: '资金托管',
                        color: Colors.blue,
                        onTap: () => context.push(RoutePath.escrowList),
                      ),
                      _MenuItem(
                        icon: Icons.payments_outlined,
                        label: '我的收益',
                        color: Colors.green,
                        onTap: () => context.push(RoutePath.myIncomeOverview),
                      ),
                      _MenuItem(
                        icon: Icons.receipt_long_outlined,
                        label: '发票申请',
                        color: Colors.orange,
                        onTap: () => context.push(RoutePath.invoiceManage),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuRow(List<_MenuItem> items) {
    return Row(
      children: items
          .map((item) => Expanded(
                child: _MenuCell(
                  icon: item.icon,
                  label: item.label,
                  color: item.color,
                  onTap: item.onTap,
                ),
              ))
          .toList(),
    );
  }

}

class _MenuItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuItem({required this.icon, required this.label, required this.color, required this.onTap});
}

class _MenuCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuCell({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
