import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// AI 机会页（E 模块，去次数化后已下线）。
///
/// AI 创作已改为按实际消耗的 token 直接从积分中扣减，
/// 「可用次数 / 兑换比例 / 次数流水」不再有意义，页面下线。
class AiChancePage extends StatelessWidget {
  const AiChancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('AI 机会'),
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
                'AI 创作已改为按实际消耗的 token 直接从积分中扣减，不再有「AI 次数」。'
                '查看积分请前往「福利中心」，查看 AI 消耗请前往「AI 记录」。',
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
