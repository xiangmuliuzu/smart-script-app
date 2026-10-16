import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../chat/data/chat_providers.dart';
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

  /// 状态卡片 + 进度步骤条
  Widget _buildStatusCard(Order order) {
    final Color color;
    final String desc;
    final int currentStep;
    switch (order.status) {
      case OrderStatus.confirmed:
        color = AppColors.primary;
        desc = '订单已确认，等待买方付款至托管';
        currentStep = 0;
      case OrderStatus.escrowPending:
        color = AppColors.warning;
        desc = '资金已托管，等待卖方交割';
        currentStep = 1;
      case OrderStatus.delivering:
        color = AppColors.warning;
        desc = '订单交割中，请配合完成相关手续';
        currentStep = 2;
      case OrderStatus.completed:
        color = AppColors.success;
        desc = '订单已完成，托管资金已释放给卖方';
        currentStep = 3;
      case OrderStatus.refunded:
        color = AppColors.text2;
        desc = '订单已退款';
        currentStep = -1;
      case OrderStatus.cancelled:
        color = AppColors.text3;
        desc = '订单已取消';
        currentStep = -1; // 取消不显示步骤
      default:
        color = AppColors.text2;
        desc = OrderStatus.label(order.status);
        currentStep = -1;
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
          // 进度步骤条（取消状态不显示）
          if (currentStep >= 0) ...[
            const SizedBox(height: 16),
            _buildProgressSteps(currentStep, color),
          ],
        ],
      ),
    );
  }

  /// 横向进度步骤条
  Widget _buildProgressSteps(int currentStep, Color activeColor) {
    const steps = ['已确认', '已托管', '交割中', '已完成'];
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // 连接线
          final lineIdx = i ~/ 2;
          final completed = lineIdx < currentStep;
          return Expanded(
            child: Container(
              height: 2,
              color: completed ? activeColor : Colors.grey.shade300,
            ),
          );
        } else {
          // 步骤圆点
          final stepIdx = i ~/ 2;
          final isActive = stepIdx <= currentStep;
          final isCurrent = stepIdx == currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: isCurrent ? 14 : 10,
                height: isCurrent ? 14 : 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? activeColor : Colors.grey.shade300,
                  border: isCurrent ? Border.all(color: activeColor.withOpacity(0.3), width: 4) : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[stepIdx],
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? activeColor : AppColors.text3,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          );
        }
      }),
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

  /// 底部操作栏：按状态与角色分化（confirmed→买方付款/取消；escrow_pending→卖方交割；delivering→买方确认收货）
  Widget _buildBottomBar(BuildContext context, WidgetRef ref, Order order, bool isBuyer) {
    final status = order.status;

    // 已确认：买方付款至托管/取消，卖方等待并联系
    if (status == OrderStatus.confirmed) {
      if (isBuyer) return _buildPayBar(context, ref, order);
      return _buildContactBar(context, ref, order, isBuyer, '等待买方付款至托管，可联系买方沟通');
    }

    // 已托管：卖方开始交割，买方等待
    if (status == OrderStatus.escrowPending) {
      if (!isBuyer) return _buildDeliverBar(context, ref, order);
      return _buildContactBar(context, ref, order, isBuyer, '资金已托管，等待卖方交割');
    }

    // 交割中：买方确认收货，卖方等待
    if (status == OrderStatus.delivering) {
      if (isBuyer) return _buildCompleteBar(context, ref, order);
      return _buildContactBar(context, ref, order, isBuyer, '交割已开始，等待买方确认收货');
    }
    // 已完成
    if (status == OrderStatus.completed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('交易已完成，如有问题请联系管理员', style: TextStyle(fontSize: 13, color: AppColors.text2)),
              ),
            ],
          ),
        ),
      );
    }

    // 已取消
    if (status == OrderStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (order.cancelReason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.text3, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('取消原因：${order.cancelReason}', style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                      ),
                    ],
                  ),
                ),
              const Text('订单已取消，可重新发起交易', style: TextStyle(fontSize: 13, color: AppColors.text2)),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// 买方付款栏：付款至托管 + 取消订单
  Widget _buildPayBar(BuildContext context, WidgetRef ref, Order order) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('付款后资金由平台托管，确认收货后才会释放给卖方',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showCancelDialog(context, ref, order),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text2,
                      side: const BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('取消订单'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => _payToEscrow(context, ref, order),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('付款至托管 ${order.amountYuan}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 卖方交割栏：开始交割
  Widget _buildDeliverBar(BuildContext context, WidgetRef ref, Order order) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('买方资金已托管，请放心开始交割',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _deliverOrder(context, ref, order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('开始交割', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 买方确认收货栏
  Widget _buildCompleteBar(BuildContext context, WidgetRef ref, Order order) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('确认收货后订单完成，托管资金将释放给卖方',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _completeOrder(context, ref, order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('确认收货', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 联系对方底部栏
  Widget _buildContactBar(BuildContext context, WidgetRef ref, Order order, bool isBuyer, String hint) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hint, style: const TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final inquiryId = order.inquiryId;
                  if (inquiryId == null) {
                    showAppToast(context, '该订单未关联询盘会话');
                    return;
                  }
                  try {
                    // 用询盘ID创建或获取 TRADE 类型会话
                    final chatRepo = ref.read(chatRepositoryProvider);
                    final session = await chatRepo.createTradeSession(inquiryId);
                    if (context.mounted) {
                      context.push(RoutePath.chatDetail(session.session.sessionId));
                    }
                  } catch (e) {
                    if (context.mounted) showAppToast(context, '创建会话失败: $e');
                  }
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: Text('联系${isBuyer ? '卖方' : '买方'}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 买方付款至托管（confirmed → escrow_pending）
  Future<void> _payToEscrow(BuildContext context, WidgetRef ref, Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('确认付款'),
        content: Text('付款 ${order.amountYuan} 至平台托管？资金将在您确认收货后释放给卖方。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('再想想')),
          TextButton(onPressed: () => Navigator.pop(dlgCtx, true), child: const Text('确认付款')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(tradeRepositoryProvider).appPayOrder(order.orderId!);
      if (context.mounted) {
        showAppToast(context, '付款成功，资金已托管');
        ref.invalidate(appOrderDetailProvider(order.orderId!));
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '付款失败：$e');
    }
  }

  /// 卖方开始交割（escrow_pending → delivering）
  Future<void> _deliverOrder(BuildContext context, WidgetRef ref, Order order) async {
    try {
      await ref.read(tradeRepositoryProvider).appDeliverOrder(order.orderId!);
      if (context.mounted) {
        showAppToast(context, '已开始交割');
        ref.invalidate(appOrderDetailProvider(order.orderId!));
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '操作失败：$e');
    }
  }

  /// 买方确认收货（delivering → completed，托管释放+收益入账）
  Future<void> _completeOrder(BuildContext context, WidgetRef ref, Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('确认收货'),
        content: const Text('确认收货后订单完成，托管资金将释放给卖方，此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('再想想')),
          TextButton(onPressed: () => Navigator.pop(dlgCtx, true), child: const Text('确认收货', style: TextStyle(color: AppColors.success))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(tradeRepositoryProvider).appCompleteOrder(order.orderId!);
      if (context.mounted) {
        showAppToast(context, '订单已完成，托管资金已释放给卖方');
        ref.invalidate(appOrderDetailProvider(order.orderId!));
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '操作失败：$e');
    }
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
                        // 二次确认
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dlgCtx) => AlertDialog(
                            title: const Text('确认取消'),
                            content: const Text('确定取消此订单？取消后不可恢复。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('再想想')),
                              TextButton(onPressed: () => Navigator.pop(dlgCtx, true), child: const Text('确定取消', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        try {
                          await ref.read(tradeRepositoryProvider).appCancelOrder(order.orderId!, reason);
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            showAppToast(context, '订单已取消');
                            ref.invalidate(appOrderDetailProvider(order.orderId!));
                            // 返回列表页
                            context.pop();
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
