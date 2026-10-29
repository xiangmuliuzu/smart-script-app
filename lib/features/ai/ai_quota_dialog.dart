import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';

/// AI 积分不足引导（E 模块，去次数化后）。
///
/// 后端 AI 创作接口（写作/润色/大纲）在积分不足时返回
/// code=400 + msg 含「积分不足」，页面捕获后调用
/// [showAiQuotaInsufficientDialog] 弹出引导：去福利中心做任务 / 看广告获取积分。
bool isQuotaInsufficientError(ApiException e) =>
    e.code == 400 && e.message.contains('积分不足');

/// 弹出「积分不足」引导弹窗。
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
          Text('积分不足'),
        ],
      ),
      content: Text(
        message ?? '当前积分不足以完成本次 AI 创作，请前往福利中心完成任务或观看广告获取积分。',
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        FilledButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push(RoutePath.welfareCenter);
          },
          icon: const Icon(Icons.card_giftcard, size: 18),
          label: const Text('去福利中心获取积分'),
        ),
      ],
    ),
  );
}
