import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_time.dart';
import '../data/chat_models.dart';

/// 成交订单系统消息气泡。
///
/// 识别 content 以 `[订单]` 开头、后跟 `{"orderId":N,"orderNo":"..."}` 的系统消息，
/// 渲染为可点击的居中卡片，点击跳转订单详情（与会话页顶部「查看订单」按钮同一功能）。
class OrderMessageBubble extends StatelessWidget {
  const OrderMessageBubble({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  static const String _prefix = '[订单]';

  /// 判断一条系统消息是否为成交订单跳转消息
  static bool isOrderMessage(ChatMessage message) =>
      message.isSystem && message.content.startsWith(_prefix);

  /// 解析卡片载荷；缺 orderId 视为无效（调用方按普通系统消息渲染）
  static OrderMessagePayload? parse(ChatMessage message) {
    if (!isOrderMessage(message)) return null;
    final json = message.content.substring(_prefix.length).trim();
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      final orderId = (decoded['orderId'] as num?)?.toInt();
      if (orderId == null) return null;
      return OrderMessagePayload(orderId, decoded['orderNo'] as String?);
    } catch (_) {
      return null;
    }
  }

  void _openOrder(BuildContext context) {
    final payload = parse(message);
    if (payload == null) return;
    context.push('${RoutePath.orderDetail}?id=${payload.orderId}');
  }

  @override
  Widget build(BuildContext context) {
    final payload = parse(message);
    if (payload == null) return const SizedBox.shrink();
    final orderNo = payload.orderNo;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
      child: Center(
        child: InkWell(
          onTap: () => _openOrder(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 16, color: AppColors.success),
                    const SizedBox(width: 4),
                    const Text(
                      '订单已生成',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                    if (orderNo != null && orderNo.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        orderNo,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.text3),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '点击查看订单',
                      style: TextStyle(fontSize: 12, color: AppColors.text2),
                    ),
                    Icon(Icons.chevron_right,
                        size: 14, color: AppColors.text3),
                  ],
                ),
                if (message.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.createdAt!),
                    style:
                        const TextStyle(fontSize: 10, color: AppColors.text3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final b = AppTime.beijing(dt);
    if (AppTime.dayDiffBeijing(dt) == 0) {
      return '${AppTime.two(b.hour)}:${AppTime.two(b.minute)}';
    }
    return '${b.month}/${b.day} ${AppTime.two(b.hour)}:${AppTime.two(b.minute)}';
  }
}

class OrderMessagePayload {
  const OrderMessagePayload(this.orderId, this.orderNo);

  final int orderId;
  final String? orderNo;
}
