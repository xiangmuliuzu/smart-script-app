import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 兑换记录页（App 端 E 模块，去次数化后已下线）。
///
/// 「积分兑换次数」功能下线后，兑换记录不再产生新数据。
class WelfareExchangeRecordsPage extends StatelessWidget {
  const WelfareExchangeRecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('兑换记录'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 56, color: AppColors.text3.withOpacity(0.5)),
              const SizedBox(height: 16),
              const Text('该功能已下线',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text1)),
              const SizedBox(height: 8),
              const Text(
                '「积分兑换 AI 次数」已下线，AI 创作直接按实际消耗的 token 扣减积分。'
                '积分获取与消耗请查看「积分明细」。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
