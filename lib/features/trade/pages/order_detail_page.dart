import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 订单详情页。
///
/// 从上到下：状态卡片 → 作品信息 → 报价信息 → 双方信息 → 订单信息 → 底部操作栏。
class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(appOrderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('订单详情'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: orderAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: '加载失败: $e'),
        data: (order) {
          final authState = ref.watch(authControllerProvider);
          final currentUserId = authState.user?.userId ?? 0;
          final isBuyer = order.buyerId == currentUserId;
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildStatusCard(order),
                      const SizedBox(height: 10),
                      _buildWorkCard(order),
                      const SizedBox(height: 10),
                      _buildQuoteCard(order),
                      const SizedBox(height: 10),
                      _buildPartyCard(order),
                      const SizedBox(height: 10),
                      _buildOrderInfoCard(order),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(context, ref, order, isBuyer),
            ],
          );
        },
      ),
    );
  }

  /// 状态卡片
  Widget _buildStatusCard(Order order) {
    final Color color;
    final String desc;
    switch (order.status) {
      case OrderStatus.confirmed:
        color = AppColors.primary;
        desc = '订单已确认，等待后续流程';
      case OrderStatus.delivering:
        color = AppColors.warning;
        desc = '订单交割中，请配合完成相关手续';
      case OrderStatus.completed:
        color = AppColors.success;
        desc = '订单已完成';
      case OrderStatus.cancelled:
        color = AppColors.text3;
        desc = '订单已取消';
      default:
        color = AppColors.text2;
        desc = OrderStatus.label(order.status);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            OrderStatus.label(order.status),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(desc, style: TextStyle(fontSize: 13, color: color.withOpacity(0.8))),
        ],
      ),
    );
  }

  /// 作品信息卡片
  Widget _buildWorkCard(Order order) {
    return _buildCard('作品信息', [
      _infoRow('作品名称', order.workTitle ?? '未知'),
      _infoRow('授权类型', LicenseType.label(order.licenseType)),
    ]);
  }

  /// 报价信息卡片
  Widget _buildQuoteCard(Order order) {
    return _buildCard('报价信息', [
      _infoRow('成交金额', order.amountYuan,
          valueStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
      _infoRow('报价ID', order.quoteId?.toString() ?? '-'),
    ]);
  }

  /// 双方信息卡片
  Widget _buildPartyCard(Order order) {
    return _buildCard('双方信息', [
      _infoRow('买方', order.buyerName ?? '用户${order.buyerId}'),
      _infoRow('卖方', order.sellerName ?? '用户${order.sellerId}'),
    ]);
  }

  /// 订单信息卡片
  Widget _buildOrderInfoCard(Order order) {
    return _buildCard('订单信息', [
      _infoRow('订单号', order.orderNo ?? '-'),
      _infoRow('创建时间', _formatDateTime(order.createdAt)),
      if (order.cancelReason != null) _infoRow('取消原因', order.cancelReason!),
    ]);
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text1)),
          const Divider(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {TextStyle? valueStyle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
          ),
          Expanded(
            child: Text(value, style: valueStyle ?? const TextStyle(fontSize: 13, color: AppColors.text1)),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏
  Widget _buildBottomBar(BuildContext context, WidgetRef ref, Order order, bool isBuyer) {
    // 已确认 + 买方 → 显示取消按钮
    if (order.status == OrderStatus.confirmed && isBuyer) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showCancelDialog(context, ref, order),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('取消订单', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      );
    }

    // 其他状态：占位说明
    if (order.status == OrderStatus.confirmed && !isBuyer) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Text('等待买方操作', style: TextStyle(fontSize: 13, color: AppColors.text3)),
      );
    }

    // D 模块功能占位
    if (order.status == OrderStatus.delivering || order.status == OrderStatus.completed) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Text('合同/托管/结算功能开发中', style: TextStyle(fontSize: 13, color: AppColors.text3)),
      );
    }

    return const SizedBox.shrink();
  }

  /// 取消订单底部弹窗
  void _showCancelDialog(BuildContext context, WidgetRef ref, Order order) {
    String? selectedReason;
    final customController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖拽手柄
                  Container(width: 36, height: 4, decoration: BoxDecoration(
                    color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  const Text('取消订单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  // 预设原因
                  ...[
                    '与卖方协商一致',
                    '作品不符合需求',
                    '价格原因',
                  ].map((r) => RadioListTile<String>(
                    title: Text(r, style: const TextStyle(fontSize: 14)),
                    value: r,
                    groupValue: selectedReason,
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setSheetState(() {
                        selectedReason = v;
                        customController.clear();
                      });
                    },
                  )),
                  RadioListTile<String>(
                    title: const Text('其他', style: TextStyle(fontSize: 14)),
                    value: 'other',
                    groupValue: selectedReason,
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setSheetState(() {
                        selectedReason = v;
                      });
                    },
                  ),
                  if (selectedReason == 'other')
                    Padding(
                      padding: const EdgeInsets.only(left: 48, right: 8, bottom: 8),
                      child: TextField(
                        controller: customController,
                        decoration: const InputDecoration(
                          hintText: '请输入取消原因',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final reason = selectedReason == 'other'
                            ? customController.text.trim()
                            : selectedReason;
                        if (reason == null || reason.isEmpty) {
                          showAppToast(context, '请选择或输入取消原因');
                          return;
                        }
                        try {
                          await ref.read(tradeRepositoryProvider).appCancelOrder(order.orderId!, reason);
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            showAppToast(context, '订单已取消');
                            ref.invalidate(appOrderDetailProvider(order.orderId!));
                          }
                        } catch (e) {
                          if (context.mounted) showAppToast(context, '取消失败：$e');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('确认取消', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
