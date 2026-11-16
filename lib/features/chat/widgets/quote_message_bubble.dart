import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/chat_models.dart';

/// 报价/议价系统消息气泡。
///
/// 识别 content 以 [报价] / [议价] / [接受] / [拒绝] 开头的系统消息，
/// 渲染为居中卡片样式；其他系统消息保持原有灰色文字样式。
class QuoteMessageBubble extends StatelessWidget {
  const QuoteMessageBubble({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  /// 判断一条系统消息是否为报价/议价类消息
  static bool isQuoteMessage(ChatMessage message) {
    if (!message.isSystem) return false;
    final c = message.content;
    return c.startsWith('[报价]') ||
        c.startsWith('[议价]') ||
        c.startsWith('[接受]') ||
        c.startsWith('[拒绝]');
  }

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final parsed = _parseQuoteContent(content);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _bgColor(parsed.tag),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borderColor(parsed.tag)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标签行
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_tagIcon(parsed.tag), size: 16, color: _tagColor(parsed.tag)),
                  const SizedBox(width: 4),
                  Text(
                    parsed.tag,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _tagColor(parsed.tag),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 详情行
              Text(
                parsed.detail,
                style: const TextStyle(fontSize: 13, color: AppColors.text1),
                textAlign: TextAlign.center,
              ),
              // 时间
              if (message.createdAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.createdAt!),
                  style: const TextStyle(fontSize: 10, color: AppColors.text3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _ParsedQuote _parseQuoteContent(String content) {
    // 格式: [标签] 详情内容
    final bracketEnd = content.indexOf(']');
    if (bracketEnd < 0) return _ParsedQuote(content, '');
    final tag = content.substring(1, bracketEnd);
    final detail = content.substring(bracketEnd + 1).trim();
    return _ParsedQuote(tag, detail);
  }

  Color _bgColor(String tag) {
    switch (tag) {
      case '报价':
        return AppColors.primary.withOpacity(0.06);
      case '议价':
        return AppColors.warning.withOpacity(0.06);
      case '接受':
        return AppColors.success.withOpacity(0.06);
      case '拒绝':
        return AppColors.danger.withOpacity(0.06);
      default:
        return AppColors.fill;
    }
  }

  Color _borderColor(String tag) {
    switch (tag) {
      case '报价':
        return AppColors.primary.withOpacity(0.2);
      case '议价':
        return AppColors.warning.withOpacity(0.2);
      case '接受':
        return AppColors.success.withOpacity(0.2);
      case '拒绝':
        return AppColors.danger.withOpacity(0.2);
      default:
        return AppColors.divider;
    }
  }

  Color _tagColor(String tag) {
    switch (tag) {
      case '报价':
        return AppColors.primary;
      case '议价':
        return AppColors.warning;
      case '接受':
        return AppColors.success;
      case '拒绝':
        return AppColors.danger;
      default:
        return AppColors.text2;
    }
  }

  IconData _tagIcon(String tag) {
    switch (tag) {
      case '报价':
        return Icons.payments_outlined;
      case '议价':
        return Icons.gavel;
      case '接受':
        return Icons.check_circle_outline;
      case '拒绝':
        return Icons.cancel_outlined;
      default:
        return Icons.info_outline;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _ParsedQuote {
  final String tag;
  final String detail;
  _ParsedQuote(this.tag, this.detail);
}
