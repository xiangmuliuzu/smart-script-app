import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../data/promotion_models.dart';
import '../data/promotion_providers.dart';
import '../widgets/promotion_widgets.dart';

/// 推广支付：展示支付宝沙箱收款二维码，轮询确认支付结果。
class PromotionPayPage extends ConsumerStatefulWidget {
  const PromotionPayPage({super.key, required this.applyId});

  final int applyId;

  @override
  ConsumerState<PromotionPayPage> createState() => _PromotionPayPageState();
}

class _PromotionPayPageState extends ConsumerState<PromotionPayPage> {
  Timer? _timer;
  PromotionPaymentOrder? _order;
  String? _error;
  bool _loading = true;
  bool _confirming = false;
  bool _paid = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await ref
          .read(promotionRepositoryProvider)
          .createPayment(widget.applyId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '创建支付失败，请稍后重试';
      });
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkPayment(silent: true),
    );
  }

  Future<void> _checkPayment({required bool silent}) async {
    if (_paid || _closed || _confirming) return;

    _confirming = true;
    if (!silent) setState(() {});

    try {
      final result = await ref
          .read(promotionRepositoryProvider)
          .confirmPayment(widget.applyId);
      if (!mounted) return;
      if (result.paid) {
        _onPaid();
        return;
      }
      if (result.closed) {
        _timer?.cancel();
        setState(() => _closed = true);
        return;
      }
      if (!silent) {
        showAppToast(context, '尚未查询到支付结果，请完成扫码后再试');
      }
    } catch (error) {
      if (!silent && mounted) {
        showAppToast(
          context,
          error is ApiException ? error.message : '查询支付结果失败，请稍后重试',
        );
      }
    } finally {
      _confirming = false;
      if (mounted && !silent) setState(() {});
    }
  }

  void _onPaid() {
    if (_paid) return;
    _timer?.cancel();
    setState(() => _paid = true);
    ref.invalidate(myPromotionsProvider);
    ref.invalidate(promotionDetailProvider(widget.applyId));
    showAppToast(context, '支付成功，推广已生效');
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) context.pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail =
        ref.watch(promotionDetailProvider(widget.applyId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('推广支付')),
      body: _buildBody(detail),
    );
  }

  Widget _buildBody(PromotionApplication? detail) {
    if (_paid) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 64, color: AppColors.success),
            SizedBox(height: 14),
            Text(
              '支付成功',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text1,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '推广将按投放时段自动生效',
              style: TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return const LoadingView(message: '正在创建支付…');
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    final order = _order;
    if (order == null) {
      return ErrorView(message: '支付信息缺失，请返回重试', onRetry: _load);
    }

    final amount = detail?.amount;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Column(
              children: [
                const Text(
                  '支付金额',
                  style: TextStyle(fontSize: 11.5, color: AppColors.text3),
                ),
                const SizedBox(height: 4),
                Text(
                  amount == null ? '—' : '¥${formatPromotionMoney(amount)}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 18),
                if (_closed) ...[
                  const Icon(
                    Icons.cancel_outlined,
                    size: 64,
                    color: AppColors.text3,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '支付单已关闭',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '请返回推广详情后重新发起支付',
                    style: TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton(
                    onPressed: () => context.pop(false),
                    child: const Text('返回详情'),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.fill,
                      borderRadius: BorderRadius.circular(AppRadius.rSmall),
                    ),
                    child: QrImageView(
                      data: order.qrCode,
                      version: QrVersions.auto,
                      size: 210,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    order.sandbox ? '支付宝沙箱环境，请使用沙箱钱包扫码支付' : '请使用支付宝扫码支付',
                    style:
                        const TextStyle(fontSize: 11.5, color: AppColors.text3),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '等待支付结果…',
                        style: TextStyle(fontSize: 12, color: AppColors.text2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _confirming
                          ? null
                          : () => _checkPayment(silent: false),
                      child: const Text('我已完成支付，刷新状态'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '支付完成后本页会自动刷新；未完成支付前请勿关闭页面。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.text3,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
