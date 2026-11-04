import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../trade/data/trade_models.dart';
import '../../trade/data/trade_providers.dart';

/// 底部报价输入卡片（嵌入输入框上方，仅 TRADE 会话显示）。
///
/// 居中展示可编辑金额，无独立发送按钮。
/// 由聊天输入框的发送按钮统一触发：金额变化时同步更新报价。
class QuoteInputCard extends ConsumerStatefulWidget {
  const QuoteInputCard({
    super.key,
    required this.inquiryId,
    required this.amountController,
    required this.budget,
  });

  final int inquiryId;
  final TextEditingController amountController;
  final int? budget; // 分

  @override
  ConsumerState<QuoteInputCard> createState() => _QuoteInputCardState();
}

class _QuoteInputCardState extends ConsumerState<QuoteInputCard> {
  bool _hasInitialized = false;

  @override
  Widget build(BuildContext context) {
    final quoteAsync = ref.watch(latestQuoteProvider(widget.inquiryId));

    return quoteAsync.when(
      loading: () => _buildCard(null),
      error: (_, __) => _buildCard(null),
      data: (quote) {
        _initFromQuote(quote);
        return _buildCard(quote);
      },
    );
  }

  void _initFromQuote(Quote? quote) {
    if (_hasInitialized) return;
    if (quote != null && quote.amount != null) {
      widget.amountController.text = (quote.amount! / 100).toStringAsFixed(2);
      _hasInitialized = true;
    }
  }

  Widget _buildCard(Quote? latestQuote) {
    if (latestQuote?.status == 'accepted') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '¥',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: TextField(
                controller: widget.amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '',
                ),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
