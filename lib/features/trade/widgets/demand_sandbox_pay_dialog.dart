import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// 支付宝沙箱收款二维码弹窗（托管付款 / 押金付款共用）。
///
/// 沿用队友订单沙箱弹窗风格：展示二维码 + 金额，每 3 秒调用一次 [confirm] 主动查单，
/// 查得已支付则关闭弹窗并返回 true。沙箱仅收款进平台商户账户，不产生真实资金流转。
/// 收款码会随商户单号轮换：查单返回 closed 时自动换新码，弹窗停留超过
/// [autoRefreshInterval] 也自动换码，二维码下方另留「刷新二维码」按钮供手动换。
class DemandSandboxPayDialog extends StatefulWidget {
  const DemandSandboxPayDialog({
    super.key,
    required this.title,
    required this.qrCode,
    required this.amountYuanText,
    required this.hint,
    required this.confirm,
    required this.onRefresh,
    this.autoRefreshInterval = const Duration(minutes: 5),
  });

  final String title;
  final String qrCode;
  final String amountYuanText;
  final String hint;
  /// 主动查单回调：返回 {paid, closed?, reason?}，paid 为 true 表示已确认支付成功；
  /// closed 为 true 表示支付宝侧该单已关闭，当前码不可能再收到款；
  /// 未支付时若带 reason（如任务已被他人接走）优先展示该文案。
  final Future<Map<String, dynamic>> Function() confirm;
  /// 换新码回调：以 refresh=true 重新发起预下单，返回 {qrCode}；
  /// 若服务端查明旧码其实已被扫付，则就地结算并返回 {paid: true}。
  final Future<Map<String, dynamic>> Function() onRefresh;
  final Duration autoRefreshInterval;

  @override
  State<DemandSandboxPayDialog> createState() => _DemandSandboxPayDialogState();
}

class _DemandSandboxPayDialogState extends State<DemandSandboxPayDialog> {
  Timer? _pollTimer;
  Timer? _rotateTimer;
  bool _checking = false;
  bool _refreshing = false;
  bool _busy = false;
  String? _message;
  late String _qrCode = widget.qrCode;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _check(silent: true),
    );
    _rotateTimer = Timer.periodic(widget.autoRefreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _rotateTimer?.cancel();
    super.dispose();
  }

  Future<void> _check({bool silent = false}) async {
    if (_busy) return;
    _busy = true;
    if (!silent) {
      setState(() {
        _checking = true;
        _message = null;
      });
    }
    var needRefresh = false;
    try {
      final result = await widget.confirm();
      if (!mounted) return;
      if (result['paid'] == true) {
        Navigator.of(context).pop(true);
      } else if (result['closed'] == true) {
        // 旧单在支付宝侧已关闭，再怎么扫也不会到账，得换一张新码
        needRefresh = true;
      } else {
        final reason = result['reason'];
        if (reason is String && reason.isNotEmpty) {
          // 任务已被他人接走这类终态原因，继续轮询没有意义
          _pollTimer?.cancel();
          setState(() => _message = reason);
        } else if (!silent) {
          setState(() => _message = '尚未查询到支付成功，请完成支付后重试');
        }
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _message = '查询失败：$e');
    } finally {
      _busy = false;
      if (mounted && !silent) setState(() => _checking = false);
    }
    if (needRefresh && mounted) await _refresh();
  }

  Future<void> _refresh() async {
    if (_busy || _refreshing) return;
    _refreshing = true;
    setState(() => _message = '正在生成新的收款码…');
    try {
      final result = await widget.onRefresh();
      if (!mounted) return;
      if (result['paid'] == true) {
        // 服务端查明旧码其实已付款并就地结算，直接按成功收尾
        Navigator.of(context).pop(true);
        return;
      }
      final qr = result['qrCode'];
      if (qr is String && qr.isNotEmpty) {
        setState(() {
          _qrCode = qr;
          _message = null;
        });
      } else {
        setState(() => _message = '暂时取不到新的收款码，请稍后重试');
      }
    } catch (e) {
      if (mounted) setState(() => _message = '刷新失败：$e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text1)),
            const SizedBox(height: 8),
            Text(widget.hint,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4)),
            const SizedBox(height: 12),
            // QrImageView 内部用 LayoutBuilder，AlertDialog 量固有宽度时会抛异常导致弹窗不显示，
            // 这里直接用 QrPainter 绘制固定尺寸。
            Container(
              width: 200,
              height: 200,
              color: Colors.white,
              child: CustomPaint(
                painter: QrPainter(
                  data: _qrCode,
                  version: QrVersions.auto,
                  gapless: true,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: (_busy || _refreshing) ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(_refreshing ? '生成新码中…' : '刷新二维码'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.text1,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: _message == null
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  _message ?? '等待支付结果…扫码完成后会自动确认',
                  style: TextStyle(
                    fontSize: 12,
                    color: _message == null ? Colors.grey.shade600 : Colors.red.shade600,
                  ),
                ),
              ],
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
