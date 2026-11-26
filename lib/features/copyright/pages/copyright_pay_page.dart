/// 版权登记费确认页：临时跳过支付宝沙箱，点击即履约并提交第三方。
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
  bool _paid = false;
  int? _applyId;
  String? _error;

  Future<void> _directPay() async {
    if (_submitting || _paid) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result =
          await ref.read(copyrightProvider).directPay(widget.payOrderId);
      if (!mounted) return;
      if (result.paid) {
        _onPaid(result.applyId);
        return;
      }
      setState(() {
        _submitting = false;
        _error = '付款未完成，请稍后重试';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is ApiException ? error.message : '付款提交失败，请稍后重试';
      });
    }
  }

  void _onPaid(int? applyId) {
    if (_paid) return;
    setState(() {
      _paid = true;
      _submitting = false;
      _applyId = applyId;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('支付成功，已提交至版权中心审核')),
    );
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final id = _applyId;
      if (id != null && id > 0) {
        context.go(RoutePath.copyrightApplicationDetailUrl(id));
      } else {
        context.go(RoutePath.copyrightApplicationListUrl());
      }
    });
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
      body: _buildBody(amount),
    );
  }

  Widget _buildBody(double? amount) {
    if (_paid) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 64, color: AppColors.success),
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
              '申请已提交至版权中心审核',
              style: TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          ],
        ),
      );
    }

    return Padding(
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
                    amount != null ? '¥${amount.toStringAsFixed(2)}' : '—',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '当前跳过沙箱支付，点击确认后直接提交版权申请',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.text2,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _submitting ? null : _directPay,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              amount != null
                                  ? '确认付款 ¥${amount.toStringAsFixed(2)}'
                                  : '确认付款',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
