import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/demand_genre.dart';
import '../../../core/theme/app_colors.dart';

/// 题材选择组（含"全部"），用于筛选弹层，不在列表页顶部常驻。
///
/// 排列规则：横向依次排列，一行满 4 个自动换行；一页最多 5 行（20 项），
/// 超过后左滑翻页，不显示页码。当前题材只有 7+1 项，只有单页，
/// 高度按实际行数收紧，不预留空行。
/// 与「我的任务」状态筛选同一套语言：白底细边 → 选中主色实心白字。
/// selectedGenreId 传 null 表示"全部"。
class DemandGenreChipRow extends StatelessWidget {
  const DemandGenreChipRow({
    super.key,
    required this.selectedGenreId,
    required this.onSelected,
    this.counts,
    this.totalCount,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final int? selectedGenreId;
  final ValueChanged<int?> onSelected;

  /// 各题材当前可接单数（广场口径）；为 null 或无项时不显角标。
  final Map<int, int>? counts;

  /// “全部”chip 的总数角标（= 可接单总数）。
  final int? totalCount;

  /// 组的外边距；筛选弹层里自带 20 内边距，可传 EdgeInsets.zero。
  final EdgeInsetsGeometry padding;

  static const int _allSentinel = -1;

  /// 每行个数：弹层可用宽约 353dp，2 字 chip 带角标约 70dp，放得下 4 个。
  static const int _columns = 4;

  /// 每页行数上限。
  static const int _rowsPerPage = 5;

  static const double _chipHeight = 32;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final ids = <int>[_allSentinel, ...DemandGenre.labels.keys];
    const perPage = _columns * _rowsPerPage;
    final pageCount = (ids.length + perPage - 1) ~/ perPage;
    // 单页时按实际行数定高；多页时统一 5 行高，翻页时高度不跳动
    final rows = pageCount > 1
        ? _rowsPerPage
        : (ids.length + _columns - 1) ~/ _columns;
    final height = rows * _chipHeight + (rows - 1) * _gap;

    return Padding(
      padding: padding,
      child: SizedBox(
        height: height,
        child: pageCount <= 1
            ? Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [for (final id in ids) _buildChip(id)],
              )
            : PageView.builder(
                itemCount: pageCount,
                itemBuilder: (context, page) {
                  final start = page * perPage;
                  final end = math.min(start + perPage, ids.length);
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Wrap(
                      spacing: _gap,
                      runSpacing: _gap,
                      children: [
                        for (var i = start; i < end; i++) _buildChip(ids[i]),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildChip(int id) {
    final isAll = id == _allSentinel;
    final selected = isAll
        ? selectedGenreId == null
        : selectedGenreId == id;
    final label = isAll ? '全部' : DemandGenre.labelOf(id);
    final count = isAll ? totalCount : counts?[id];
    return _Chip(
      label: label,
      selected: selected,
      count: count,
      onTap: () => onSelected(isAll ? null : id),
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
      // 注意：不要给 AnimatedContainer 设 alignment —— 在 Wrap 的有界宽度下
      // 会撑满整行，导致每个 chip 独占一行（竖排）。
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
                  color: selected
                      ? Colors.white.withOpacity(0.24)
                      : AppColors.fill,
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
