import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// 支付宝沙箱收款二维码弹窗（托管付款 / 押金付款共用）。
///
/// 沿用队友订单沙箱弹窗风格：展示二维码 + 金额，由调用方传入 [confirm] 主动查单，
/// 查得已支付则关闭弹窗并返回 true。沙箱仅收款进平台商户账户，不产生真实资金流转。
class DemandSandboxPayDialog extends StatefulWidget {
  const DemandSandboxPayDialog({
    super.key,
    required this.title,
    required this.qrCode,
    required this.amountYuanText,
    required this.hint,
    required this.confirm,
  });

  final String title;
  final String qrCode;
  final String amountYuanText;
  final String hint;
  /// 主动查单回调：返回 {paid, reason?}，paid 为 true 表示已确认支付成功；
  /// 未支付时若带 reason（如任务已被他人接走）优先展示该文案。
  final Future<Map<String, dynamic>> Function() confirm;

  @override
  State<DemandSandboxPayDialog> createState() => _DemandSandboxPayDialogState();
}

class _DemandSandboxPayDialogState extends State<DemandSandboxPayDialog> {
  bool _checking = false;
  String? _message;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final result = await widget.confirm();
      if (!mounted) return;
      if (result['paid'] == true) {
        Navigator.of(context).pop(true);
        return;
      }
      final reason = result['reason'];
      setState(() => _message = reason is String && reason.isNotEmpty
          ? reason
          : '尚未查询到支付成功，请完成支付后重试');
    } catch (e) {
      if (mounted) setState(() => _message = '查询失败：$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('金额 ¥${widget.amountYuanText}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 8),
            Text(widget.hint,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4)),
            const SizedBox(height: 12),
            QrImageView(data: widget.qrCode, size: 200),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!, style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.pop(context, false),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: _checking ? null : _check,
          child: Text(_checking ? '查询中…' : '我已完成支付'),
        ),
      ],
    );
  }
}
