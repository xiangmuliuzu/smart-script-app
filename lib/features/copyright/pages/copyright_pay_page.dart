/// 版权登记费确认页：临时跳过支付宝沙箱，确认后直接履约并提交第三方。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/copyright_providers.dart';

class CopyrightPayPage extends ConsumerStatefulWidget {
  const CopyrightPayPage({
    super.key,
    required this.payOrderId,
    this.feeAmount,
  });

  final int payOrderId;
  final double? feeAmount;

  @override
  ConsumerState<CopyrightPayPage> createState() => _CopyrightPayPageState();
}

class _CopyrightPayPageState extends ConsumerState<CopyrightPayPage> {
  bool _submitting = false;
  bool _done = false;

  Future<void> _confirmPay() async {
    if (_submitting || _done) return;
    setState(() => _submitting = true);
    try {
      final result =
          await ref.read(copyrightProvider).directPay(widget.payOrderId);
      if (!mounted) return;
      if (!result.paid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提交失败，请稍后重试')),
        );
        return;
      }
      setState(() => _done = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交至版权中心审核')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      final applyId = result.applyId;
      if (applyId != null && applyId > 0) {
        context.go(RoutePath.copyrightApplicationDetailUrl(applyId));
      } else {
        context.go(RoutePath.copyrightApplicationListUrl());
      }
    } catch (error) {
      if (!mounted) return;
      final message =
          error is ApiException ? error.message : '付款提交失败，请稍后重试';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted && !_done) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.feeAmount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('确认付款'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      '应付登记费',
                      style: TextStyle(fontSize: 14, color: AppColors.text3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      amount != null
                          ? '¥${amount.toStringAsFixed(2)}'
                          : '确认后提交',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '当前为临时直付：确认后直接创建申请并提交第三方版权中心，暂不走支付宝沙箱。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting || _done ? null : _confirmPay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        amount != null
                            ? '确认付款 ¥${amount.toStringAsFixed(2)}'
                            : '确认付款并提交',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
