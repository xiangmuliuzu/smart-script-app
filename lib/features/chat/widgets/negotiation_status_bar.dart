import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../trade/data/trade_models.dart';
import '../../trade/data/trade_providers.dart';

/// 顶部议价状态栏（嵌入消息列表顶部，仅 TRADE 会话显示）。
///
/// 展示当前报价金额（初始为询盘预算，有报价后为最新报价），
/// 对方发的待确认报价可点击"接受"。
class NegotiationStatusBar extends ConsumerStatefulWidget {
  const NegotiationStatusBar({
    super.key,
    required this.inquiryId,
    required this.currentUserId,
    required this.isBuyer,
    required this.isSeller,
    required this.budget,
  });

  final int inquiryId;
  final int currentUserId;
  final bool isBuyer;
  final bool isSeller;
  final int? budget; // 分

  @override
  ConsumerState<NegotiationStatusBar> createState() => _NegotiationStatusBarState();
}

class _NegotiationStatusBarState extends ConsumerState<NegotiationStatusBar> {
  bool _isAccepting = false;

  int get inquiryId => widget.inquiryId;
  int get currentUserId => widget.currentUserId;
  bool get isBuyer => widget.isBuyer;
  bool get isSeller => widget.isSeller;
  int? get budget => widget.budget;
  @override
  Widget build(BuildContext context) {
    final quoteAsync = ref.watch(latestQuoteProvider(inquiryId));

    return quoteAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (quote) => _buildContent(context, quote),
    );
  }

  Widget _buildContent(BuildContext context, Quote? quote) {
    // 确定展示金额：有报价用报价，否则用询盘预算
    final int? amountFen = quote?.amount ?? budget;
    if (amountFen == null) return const SizedBox.shrink();

    final String amountText = '¥${(amountFen / 100).toStringAsFixed(2)}';
    final bool canAccept = _canAccept(quote);
    final bool isAccepted = quote?.status == 'accepted';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isAccepted
            ? AppColors.success.withOpacity(0.06)
            : AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAccepted
              ? AppColors.success.withOpacity(0.3)
              : AppColors.divider,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：标签 + 金额
          Row(
            children: [
              // 来源标签
              _buildSourceTag(quote),
              const Spacer(),
              // 金额
              Text(
                amountText,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isAccepted ? AppColors.success : AppColors.text1,
                ),
              ),
            ],
          ),
          // 第二行：状态说明 + 接受按钮
          if (isAccepted) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                const SizedBox(width: 4),
                const Text(
                  '已成交',
                  style: TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ] else if (canAccept) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isAccepting ? null : () => _acceptQuote(context, quote!.quoteId!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isAccepting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('接受', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ] else if (quote != null && _isMyPending(quote)) ...[
            const SizedBox(height: 4),
            const Center(
              child: Text(
                '等待对方确认',
                style: TextStyle(fontSize: 11, color: AppColors.text3),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceTag(Quote? quote) {
    if (quote == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.text3.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '预算金额',
          style: TextStyle(fontSize: 10, color: AppColors.text3, fontWeight: FontWeight.w500),
        ),
      );
    }

    final isSellerQuote = quote.role == 'seller';
    final Color color = isSellerQuote ? AppColors.primary : AppColors.warning;
    final String label = isSellerQuote ? '卖方报价' : '买方议价';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }

  bool _canAccept(Quote? quote) {
    if (quote == null) return false;
    if (quote.status == 'pending' && isBuyer) return true;
    if (quote.status == 'pending_seller' && isSeller) return true;
    return false;
  }

  bool _isMyPending(Quote quote) {
    if (quote.status == 'pending' && isSeller) return true;
    if (quote.status == 'pending_seller' && isBuyer) return true;
    return false;
  }

  Future<void> _acceptQuote(BuildContext context, int quoteId) async {
    if (_isAccepting) return;
    setState(() { _isAccepting = true; });
    try {
      final result = await ref.read(tradeRepositoryProvider).appAcceptQuote(quoteId);
      if (context.mounted) {
        final orderId = result['orderId'] as int?;
        if (orderId != null) {
          showAppToast(context, '已接受报价，正在生成订单...');
          // 跳转订单详情，返回时刷新状态
          await context.push('${RoutePath.orderDetail}?id=$orderId');
        } else {
          showAppToast(context, '已接受报价');
        }
        // 返回后刷新议价状态
        ref.invalidate(latestQuoteProvider(inquiryId));
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '操作失败：$e');
    } finally {
      if (mounted) setState(() { _isAccepting = false; });
    }
  }
}
