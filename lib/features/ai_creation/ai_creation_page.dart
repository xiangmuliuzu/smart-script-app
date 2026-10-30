import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../welfare/data/welfare_providers.dart';

/// AI 创作中心（App 端 E 模块，原「我的剧本」入口）。
///
/// 布局：
///   顶部资产卡：积分（去次数化后不再展示 AI 机会）
///   功能宫格：AI 大纲 / AI 写作 / AI 润色 / AI 记录
/// 审核进度由「我的作品」页承载（组员已实现），此处不重复入口。
class AiCreationPage extends ConsumerWidget {
  const AiCreationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 创作'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          _AssetCard(),
          SizedBox(height: 12),
          _FeatureCard(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 顶部资产卡：渐变底 + 积分。
class _AssetCard extends ConsumerWidget {
  const _AssetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(welfareAssetProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r),
      ),
      child: asset.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        error: (_, __) => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('资产加载失败', style: TextStyle(color: Colors.white)),
          ),
        ),
        data: (value) => Row(
          children: [
            _AssetItem(label: '积分', value: '${value.points.balance}'),
          ],
        ),
      ),
    );
  }
}

class _AssetItem extends StatelessWidget {
  const _AssetItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

/// 功能宫格卡（3 列 2 行）。
class _FeatureCard extends StatelessWidget {
  const _FeatureCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const columns = 3;
          final cellWidth = constraints.maxWidth / columns;
          return Wrap(
            children: [
              for (final entry in _entries(context))
                SizedBox(
                  width: cellWidth,
                  height: 92,
                  child: entry,
                ),
            ],
          );
        },
      ),
    );
  }

  /// 功能入口定义。审核进度跳「我的作品」，其余提示建设中。
  List<Widget> _entries(BuildContext context) {
    return [
      _FeatureCell(
        icon: Icons.auto_stories,
        label: 'AI 剧本',
        onTap: () => context.push(RoutePath.aiOutline),
      ),
      _FeatureCell(
        icon: Icons.border_color,
        label: 'AI 写作',
        onTap: () => context.push(RoutePath.aiWrite),
      ),
      _FeatureCell(
        icon: Icons.movie_creation_outlined,
        label: 'AI 分镜',
        onTap: () => context.push(RoutePath.aiStoryboard),
      ),
      _FeatureCell(
        icon: Icons.auto_fix_high,
        label: 'AI 润色',
        onTap: () => context.push(RoutePath.aiPolish),
      ),
      _FeatureCell(
        icon: Icons.history,
        label: 'AI 记录',
        onTap: () => context.push(RoutePath.aiRecords),
      ),
    ];
  }
}

class _FeatureCell extends StatelessWidget {
  const _FeatureCell({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(fontSize: 13, color: AppColors.text1)),
        ],
      ),
    );
  }
}
