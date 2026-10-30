import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../chat/data/chat_providers.dart';
import '../../copyright/data/copyright_models.dart';
import '../../copyright/data/copyright_providers.dart';
import '../data/contract_providers.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 订单详情页。
///
/// 从上到下：状态卡片 → 作品信息 → 报价信息 → 合同信息 → 双方信息 → 订单信息 → 底部操作栏。
class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(appOrderDetailProvider(orderId));
    final contractAsync = ref.watch(contractByOrderProvider(orderId));
    final deliveryAsync = ref.watch(deliveryByOrderProvider(orderId));

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
          final contract = contractAsync.valueOrNull;
          final delivery = deliveryAsync.valueOrNull;
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildStatusCard(order, delivery),
                      const SizedBox(height: 10),
                      _buildWorkCard(order),
                      const SizedBox(height: 10),
                      _buildQuoteCard(order),
                      if (contract != null) ...[
                        const SizedBox(height: 10),
                        _buildContractCard(context, order, contract),
                      ],
                      if (delivery != null) ...[
                        const SizedBox(height: 10),
                        _buildDeliveryCard(context, ref, order, delivery),
                      ],
                      const SizedBox(height: 10),
                      _buildPartyCard(order),
                      const SizedBox(height: 10),
                      _buildOrderInfoCard(order),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(context, ref, order, isBuyer, delivery),
            ],
          );
        },
      ),
    );
  }

  /// 状态卡片 + 进度步骤条
  Widget _buildStatusCard(Order order, CopyrightDelivery? delivery) {
    final Color color;
    final String desc;
    final int currentStep;
    switch (order.status) {
      case OrderStatus.confirmed:
        color = AppColors.primary;
        desc = '订单已确认，请双方签署合同';
        currentStep = 0;
      case OrderStatus.paying:
        color = AppColors.warning;
        desc = '合同已签署，等待买方付款';
        currentStep = 1;
      case OrderStatus.delivering:
        color = AppColors.warning;
        desc = delivery?.status == 'pending_confirm'
            ? '交割材料已提交，待买方确认'
            : '订单交割中，请配合完成相关手续';
        currentStep = 2;
      case OrderStatus.completed:
        color = AppColors.success;
        desc = '订单已完成';
        currentStep = 3;
      case OrderStatus.refunded:
        color = AppColors.text2;
        desc = '订单已退款';
        currentStep = -1;
      case OrderStatus.cancelled:
        color = AppColors.text3;
        desc = '订单已取消';
        currentStep = -1;
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
    const steps = ['待签署', '付款中', '交割中', '已完成'];
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

  /// 合同信息卡片
  Widget _buildContractCard(BuildContext context, Order order, ContractDetail contract) {
    final pdfUrl = contract.signedPdfUrl;
    final hasContent = contract.content != null && contract.content!.isNotEmpty;
    return _buildCard('合同信息', [
      _infoRow('合同编号', contract.contractNo ?? '-'),
      _infoRow('签署状态', contract.statusLabel),
      _infoRow('买方签署', contract.isBuyerSigned ? '已签署' : '未签署'),
      if (contract.buyerSignTime != null) _infoRow('买方签署时间', contract.buyerSignTime!),
      _infoRow('卖方签署', contract.isSellerSigned ? '已签署' : '未签署'),
      if (contract.sellerSignTime != null) _infoRow('卖方签署时间', contract.sellerSignTime!),
      // 查看合同原文（HTML WebView，APP 内展示）
      if (hasContent) ...[
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showContractContent(context, contract),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('查看合同内容', style: TextStyle(fontSize: 14)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
      if (contract.isCompleted && pdfUrl != null && pdfUrl.isNotEmpty) ...[
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openSignedPdf(context, pdfUrl),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('查看签署完成 PDF', style: TextStyle(fontSize: 14)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text2,
              side: const BorderSide(color: AppColors.divider),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    ]);
  }

  /// 在 APP 内以 WebView 全屏展示合同 HTML 内容（含签名/印章图片）。
  void _showContractContent(BuildContext context, ContractDetail contract) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ContractContentView(contract: contract),
      ),
    );
  }

  /// 打开签署完成 PDF：/profile 为 root-relative，拼站点 origin；公开静态资源无需鉴权。
  /// 本页为 ConsumerWidget 无 State.mounted，用 context.mounted 判定。
  Future<void> _openSignedPdf(BuildContext context, String pdfUrl) async {
    String full;
    try {
      full = '${Uri.parse(AppConfig.baseUrl).origin}$pdfUrl';
    } catch (_) {
      full = '${AppConfig.baseUrl}$pdfUrl';
    }
    final launched = await launchUrl(Uri.parse(full), mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      showAppToast(context, '无法打开 PDF，请稍后重试');
    }
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

  Widget _buildDeliveryCard(
    BuildContext context,
    WidgetRef ref,
    Order order,
    CopyrightDelivery delivery,
  ) {
    final fileCount = delivery.files?.length ?? 0;
    return _buildCard('交割信息', [
      _infoRow('交割单号', delivery.deliveryNo),
      _infoRow('交割状态', delivery.status.deliveryStatusName),
      if (delivery.uploadTime != null) _infoRow('提交时间', delivery.uploadTime!),
      _infoRow('交割文件', fileCount > 0 ? '$fileCount 个' : '暂未上传'),
      if (delivery.certNo != null && delivery.certNo!.isNotEmpty)
        _infoRow('版权证书号', delivery.certNo!),
      const SizedBox(height: 4),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _openDeliveryPage(context, ref, order),
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('查看交割详情', style: TextStyle(fontSize: 14)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    ]);
  }

  /// 底部操作栏：按状态与角色分化
  Widget _buildBottomBar(BuildContext context, WidgetRef ref, Order order, bool isBuyer, CopyrightDelivery? delivery) {
    final status = order.status;

    // 待签署：显示合同签署入口（双方签满后后端自动进入付款中）
    if (status == OrderStatus.confirmed) {
      return _buildContractSignBar(context, ref, order);
    }

    // 付款中：买方付款，卖方等待
    if (status == OrderStatus.paying) {
      if (isBuyer) return _buildPayBar(context, ref, order);
      return _buildContactBar(context, ref, order, isBuyer, '合同已签署，等待买方付款');
    }

    // 交割中：按交割单状态区分上传 / 待确认
    if (status == OrderStatus.delivering) {
      final uploaded = delivery?.status == 'pending_confirm' || delivery?.status == 'completed';
      if (isBuyer) {
        if (uploaded) {
          return _buildGoDeliveryBar(
            context,
            ref,
            order,
            hint: '卖方已提交交割材料，请确认收货',
            buttonLabel: '去确认收货',
          );
        }
        return _buildGoDeliveryBar(
          context,
          ref,
          order,
          hint: '等待卖方上传交割材料',
          buttonLabel: '查看交割',
          outlined: true,
        );
      }
      if (uploaded) {
        return _buildGoDeliveryBar(
          context,
          ref,
          order,
          hint: '交割材料已提交，等待买方确认',
          buttonLabel: '待买方确认',
          outlined: true,
        );
      }
      return _buildGoDeliveryBar(
        context,
        ref,
        order,
        hint: '请上传版权证书等交割材料',
        buttonLabel: '去交割',
      );
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

    return const SizedBox.shrink();
  }

  /// 合同签署栏：查看并签署合同
  Widget _buildContractSignBar(BuildContext context, WidgetRef ref, Order order) {
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
            const Text('合同尚未完成签署，请双方各自完成签署后再进行付款',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push('${RoutePath.contractSign}?orderId=${order.orderId}');
                },
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('查看并签署合同', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 取消订单：仅合同双签完成前（confirmed）可取消，买卖双方任一方均可发起
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancelOrder(context, ref, order),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('取消订单', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 买方付款栏
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
            const Text('合同已签署完成，请买方付款，付款后订单进入交割',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _payOrder(context, ref, order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('付款 ${order.amountYuan}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoDeliveryBar(
    BuildContext context,
    WidgetRef ref,
    Order order, {
    required String hint,
    required String buttonLabel,
    bool outlined = false,
  }) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    final child = Text(buttonLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
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
              child: outlined
                  ? OutlinedButton(
                      onPressed: () => _openDeliveryPage(context, ref, order),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: shape,
                      ),
                      child: child,
                    )
                  : ElevatedButton(
                      onPressed: () => _openDeliveryPage(context, ref, order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: shape,
                      ),
                      child: child,
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

  /// 支付宝沙箱：显示二维码，并由服务端向支付宝查询确认。
  Future<void> _payOrder(BuildContext context, WidgetRef ref, Order order) async {
    final id = order.orderId!;
    try {
      final data = await ref.read(tradeRepositoryProvider).appPayOrder(id);
      if (!context.mounted) return;
      final paid = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _SandboxPaymentDialog(orderId: id, qrCode: data['qrCode'] as String),
      );
      if (paid == true && context.mounted) {
        showAppToast(context, '沙箱支付已确认，订单进入交割');
        ref.invalidate(appOrderDetailProvider(id));
        ref.invalidate(deliveryByOrderProvider(id));
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '发起沙箱支付失败：$e');
    }
  }

  Future<void> _openDeliveryPage(BuildContext context, WidgetRef ref, Order order) async {
    final orderId = order.orderId;
    if (orderId == null) return;
    try {
      final delivery = await ref.read(copyrightProvider).loadDeliveryByOrder(orderId);
      if (!context.mounted) return;
      if (delivery == null) {
        showAppToast(context, '暂无交割单，请稍后重试');
        return;
      }
      await context.push(
        '${RoutePath.copyrightApplicationDetail}?id=${delivery.deliveryId}&type=delivery',
      );
      if (context.mounted) {
        ref.invalidate(appOrderDetailProvider(orderId));
        ref.invalidate(deliveryByOrderProvider(orderId));
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '打开交割失败：$e');
    }
  }

  /// 取消订单（仅 confirmed，双方签署完成前；买卖双方任一方）
  Future<void> _cancelOrder(BuildContext context, WidgetRef ref, Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('取消订单'),
        content: const Text('确定取消该订单吗？合同双方签署完成后将不可取消。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('再想想')),
          TextButton(onPressed: () => Navigator.pop(dlgCtx, true), child: const Text('确定取消', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(tradeRepositoryProvider).appCancelOrder(order.orderId!);
      if (context.mounted) {
        showAppToast(context, '订单已取消');
        ref.invalidate(appOrderDetailProvider(order.orderId!));
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '取消失败：$e');
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 合同内容全屏展示页（WebView 渲染 HTML，含签名/印章图片）。
class _ContractContentView extends StatefulWidget {
  const _ContractContentView({required this.contract});

  final ContractDetail contract;

  @override
  State<_ContractContentView> createState() => _ContractContentViewState();
}

class _ContractContentViewState extends State<_ContractContentView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadHtmlString(
        widget.contract.content ?? '<p>合同内容加载中...</p>',
        baseUrl: AppConfig.baseUrl,
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('合同内容 · ${widget.contract.contractNo ?? ''}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // 签署状态提示条
          _buildStatusBanner(),
          // WebView 合同正文
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final contract = widget.contract;
    if (contract.isCompleted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: AppColors.success.withOpacity(0.08),
        child: Row(
          children: [
            const Icon(Icons.verified, color: AppColors.success, size: 16),
            const SizedBox(width: 6),
            Text(
              '合同已完成签署',
              style: TextStyle(fontSize: 13, color: AppColors.success.withOpacity(0.9), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.warning.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.warning, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              contract.statusLabel,
              style: TextStyle(fontSize: 13, color: AppColors.warning.withOpacity(0.9), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _SandboxPaymentDialog extends ConsumerStatefulWidget {
  const _SandboxPaymentDialog({required this.orderId, required this.qrCode});
  final int orderId;
  final String qrCode;
  @override
  ConsumerState<_SandboxPaymentDialog> createState() => _SandboxPaymentDialogState();
}

class _SandboxPaymentDialogState extends ConsumerState<_SandboxPaymentDialog> {
  bool _checking = false;
  String? _message;
  Future<void> _check() async {
    setState(() { _checking = true; _message = null; });
    try {
      final paid = await ref.read(tradeRepositoryProvider).confirmSandboxPayment(widget.orderId);
      if (!mounted) return;
      if (paid) { Navigator.of(context).pop(true); return; }
      setState(() => _message = '尚未查询到支付成功，请完成支付后重试');
    } catch (e) {
      if (mounted) setState(() => _message = '查询失败：$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('支付宝沙箱支付'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('测试支付，不会产生真实资金。请使用另一台设备上的支付宝沙箱钱包扫码。'),
      const SizedBox(height: 12),
      QrImageView(data: widget.qrCode, size: 200),
      if (_message != null) Text(_message!),
    ])),
    actions: [
      TextButton(onPressed: _checking ? null : () => Navigator.pop(context, false), child: const Text('关闭')),
      TextButton(onPressed: _checking ? null : _check, child: Text(_checking ? '查询中…' : '查询支付结果')),
    ],
  );
}
