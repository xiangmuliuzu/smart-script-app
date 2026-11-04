import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/demand_providers.dart';

/// 任务广场 Hero 横幅：主题色渐变 + 标题 + 发布按钮 + 可接单统计胶囊。
///
/// stats 允许为 null（首屏加载），此时统计胶囊显示 "--" 占位。
class DemandHeroBanner extends StatelessWidget {
  const DemandHeroBanner({super.key, required this.stats, this.onPublish});

  final DemandStats? stats;

  /// 发布按钮行为覆盖：广场页传入后在发布/托管流程 pop 返回时刷新列表与统计。
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF3B6BB5)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.24),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '任务广场',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.15,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '找好本子 · 找好人',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              _PublishButton(
                  onTap: onPublish ??
                      () => context.push(RoutePath.demandPost)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Pill(label: '可接单', value: _fmt(stats?.openCount)),
              const SizedBox(width: 8),
              _Pill(label: '奖金池', value: _fmtYuan(stats?.prizePoolYuan)),
              const SizedBox(width: 8),
              _Pill(label: '今日新增', value: _fmt(stats?.todayNewCount)),
            ],
          ),
        ],
      ),
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

class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
              SizedBox(width: 4),
              Text(
                '发布任务',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.22), width: 0.6),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.85),
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
