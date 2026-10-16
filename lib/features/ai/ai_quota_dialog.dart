import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';

/// AI 次数不足引导（E 模块）。
///
/// 后端 AI 创作接口（写作/润色/大纲）在可用次数不足 1 次时返回
/// code=400 + msg「AI次数不足，当前可用: X 次」，页面捕获后调用
/// [showAiQuotaInsufficientDialog] 弹出引导：去积分兑换 / 看广告获取。
bool isQuotaInsufficientError(ApiException e) =>
    e.code == 400 && e.message.contains('次数不足');

/// 弹出「AI 次数不足」引导弹窗。
Future<void> showAiQuotaInsufficientDialog(
  BuildContext context, {
  String? message,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.error_outline, color: Colors.deepOrange, size: 28),
          SizedBox(width: 8),
          Text('AI 次数不足'),
        ],
      ),
      content: Text(
        message ?? '当前 AI 可用次数已用完，可兑换次数或观看广告获取。',
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push(RoutePath.welfareExchange);
          },
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('积分兑换'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push(RoutePath.welfareCenter);
          },
          icon: const Icon(Icons.ondemand_video, size: 18),
          label: const Text('看广告获取'),
        ),
      ],
    ),
  );
}
