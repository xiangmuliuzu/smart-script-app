import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// AI 次数兑换页（App 端 E 模块，去次数化后已下线）。
///
/// AI 创作已改为按实际消耗的 token 直接从积分中扣减，
/// 不再存在「次数」概念，积分兑换次数功能下线。
class WelfareExchangePage extends StatelessWidget {
  const WelfareExchangePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('积分兑换'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined,
                  size: 56, color: AppColors.text3.withOpacity(0.5)),
              const SizedBox(height: 16),
              const Text('该功能已下线',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text1)),
              const SizedBox(height: 8),
              const Text(
                'AI 创作已改为按实际消耗的 token 直接从积分中扣减，不再需要「积分兑换次数」。'
                '获取积分请前往福利中心完成任务或观看广告。',
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
