import 'package:flutter/material.dart';

import '../../../core/constants/demand_task_type.dart';
import '../../../core/theme/app_colors.dart';

/// 任务类型选择组（含"全部"），用于筛选弹层，不在列表页顶部常驻。
///
/// 只有 3 类，单行排布即可，无需像题材那样分页。
/// 与 [DemandGenreChipRow] 同一套语言：白底细边 → 选中主色实心白字。
/// selectedTaskType 传 null 表示"全部"。
class DemandTaskTypeChipRow extends StatelessWidget {
  const DemandTaskTypeChipRow({
    super.key,
    required this.selectedTaskType,
    required this.onSelected,
    this.counts,
    this.totalCount,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final String? selectedTaskType;
  final ValueChanged<String?> onSelected;

  /// 各类型当前可接单数（广场口径）；为 null 或无项时不显角标。
  final Map<String, int>? counts;

  /// “全部”chip 的总数角标（= 可接单总数）。
  final int? totalCount;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Chip(
            label: '全部',
            selected: selectedTaskType == null,
            count: totalCount,
            onTap: () => onSelected(null),
          ),
          for (final type in DemandTaskType.values)
            _Chip(
              label: DemandTaskType.labelOf(type),
              selected: selectedTaskType == type,
              count: counts?[type],
              onTap: () => onSelected(type),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primary : AppColors.card;
    final border = selected ? AppColors.primary : AppColors.divider;
    final fg = selected ? Colors.white : AppColors.text2;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // 不给 AnimatedContainer 设 alignment：在 Wrap 的有界宽度下会撑满整行，
      // 导致每个 chip 独占一行。
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                height: 1.1,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withOpacity(0.24) : AppColors.fill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: selected ? Colors.white : AppColors.text3,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
