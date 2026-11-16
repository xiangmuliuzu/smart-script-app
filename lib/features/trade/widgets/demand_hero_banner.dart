import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/demand_providers.dart';

/// 任务广场页头：引导文案 + 三项统计。
///
/// 视觉与首页/我的页对齐：页头直接落在全局冰蓝渐变上，统计数字收进
/// 白色圆角卡片（12 圆角 + 轻阴影），不再使用深蓝渐变大色块。
/// stats 允许为 null（首屏加载），此时统计值显示 "--" 占位。
class DemandHeroBanner extends StatelessWidget {
  const DemandHeroBanner({super.key, required this.stats});

  final DemandStats? stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 2, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TASK SQUARE · 公开接单',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text3,
                ),
              ),
              SizedBox(height: 5),
              Text(
                '平台发布任务，接单即锁定赏金',
                style: TextStyle(fontSize: 12, color: AppColors.text2, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StatsCard(stats: stats),
      ],
    );
  }

  static String _fmt(int? v) => v == null ? '--' : '$v';

  /// 奖金池（整元）：空→占位；≥ 1 万→"x.y万"；否则直接元数。
  static String _fmtYuan(int? v) {
    if (v == null) return '--';
    if (v >= 10000) {
      final w = v / 10000;
      final s = w >= 10 ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
      return '¥$s万';
    }
    return '¥$v';
  }
}

/// 三项统计：白卡三栏，栏间细竖线分隔。
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final DemandStats? stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.r)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          _StatCell(label: '可接单', value: DemandHeroBanner._fmt(stats?.openCount)),
          const _CellDivider(),
          _StatCell(
            label: '奖金池',
            value: DemandHeroBanner._fmtYuan(stats?.prizePoolYuan),
            highlight: true,
          ),
          const _CellDivider(),
          _StatCell(label: '今日新增', value: DemandHeroBanner._fmt(stats?.todayNewCount)),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;

  /// 金额用强调橙，是本页唯一的暖色重点，其余数字统一主色。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: highlight ? AppColors.accent : AppColors.text1,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.text3)),
        ],
      ),
    );
  }
}

class _CellDivider extends StatelessWidget {
  const _CellDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 0.8, height: 26, color: AppColors.divider);
  }
}
