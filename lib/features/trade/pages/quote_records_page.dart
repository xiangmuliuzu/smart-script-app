import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 报价记录页（分工条目 11）：查看多次报价和议价记录（只读）。
///
/// 仅展示某询盘下的全部报价/议价历史，不提供操作入口。
/// 报价/议价操作统一在交易会话的议价卡片中完成。
class QuoteRecordsPage extends ConsumerWidget {
  const QuoteRecordsPage({
    super.key,
    required this.inquiryId,
    this.workTitle,
  });

  final int inquiryId;
  final String? workTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesAsync = ref.watch(appQuoteListProvider(inquiryId));

    return Scaffold(
      appBar: AppBar(
        title: Text(workTitle != null && workTitle!.isNotEmpty
            ? '报价记录 - $workTitle'
            : '报价记录'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: quotesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (quotes) => _buildList(quotes),
      ),
    );
  }

  Widget _buildList(List<Quote> quotes) {
    if (quotes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: AppColors.text3),
            SizedBox(height: 12),
            Text('暂无报价记录', style: TextStyle(fontSize: 15, color: AppColors.text3)),
          ],
        ),
      );
    }

    // 按时间倒序
    final sorted = List<Quote>.from(quotes)
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildQuoteCard(sorted[index]),
    );
  }

  Widget _buildQuoteCard(Quote quote) {
    final isSellerQuote = quote.role == 'seller';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSellerQuote ? AppColors.primary.withOpacity(0.3) : AppColors.warning.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：角色标签 + 状态
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSellerQuote
                  ? AppColors.primary.withOpacity(0.05)
                  : AppColors.warning.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSellerQuote ? AppColors.primary : AppColors.warning,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isSellerQuote ? '卖方报价' : '买方议价',
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                _statusBadge(quote.status),
              ],
            ),
          ),

          // 内容
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 金额
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      quote.amountYuan,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.text1),
                    ),
                    const Spacer(),
                    if (quote.validDays != null)
                      Text('有效期 ${quote.validDays}天', style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                  ],
                ),
                const SizedBox(height: 8),

                // 授权类型
                if (quote.licenseType != null)
                  Text('授权类型：${_licenseLabel(quote.licenseType)}', style: const TextStyle(fontSize: 13, color: AppColors.text2)),

                // 备注
                if (quote.message != null && quote.message!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('备注：${quote.message}', style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                ],

                // 时间
                if (quote.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text('${quote.createdAt}', style: const TextStyle(fontSize: 11, color: AppColors.text3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String? status) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = AppColors.warning;
        label = '待买方确认';
      case 'pending_seller':
        color = AppColors.primary;
        label = '待卖方确认';
      case 'accepted':
        color = AppColors.success;
        label = '已接受';
      case 'rejected':
        color = AppColors.danger;
        label = '已拒绝';
      case 'expired':
        color = AppColors.text3;
        label = '已过期';
      default:
        color = AppColors.text3;
        label = status ?? '未知';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  String _licenseLabel(String? type) {
    switch (type) {
      case 'exclusive': return '独家授权';
      case 'non_exclusive': return '非独家授权';
      case 'adaptation': return '改编授权';
      default: return type ?? '-';
    }
  }
}
