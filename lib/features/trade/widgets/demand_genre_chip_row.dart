import 'package:flutter/material.dart';

import '../../../core/constants/demand_genre.dart';

/// 题材横向滑动 chips（含"全部"）。
///
/// 选中态：题材主题色实心 + 白字；未选中：主题色淡底 + 主题色文字。
/// selectedGenreId 传 null 表示"全部"。
class DemandGenreChipRow extends StatelessWidget {
  const DemandGenreChipRow({
    super.key,
    required this.selectedGenreId,
    required this.onSelected,
    this.counts,
    this.totalCount,
  });

  final int? selectedGenreId;
  final ValueChanged<int?> onSelected;

  /// 各题材当前可接单数（广场口径）；为 null 或无项时不显角标。
  final Map<int, int>? counts;

  /// “全部”chip 的总数角标（= 可接单总数）。
  final int? totalCount;

  static const int _allSentinel = -1;

  @override
  Widget build(BuildContext context) {
    // 首项"全部" + 后续题材项
    final ids = <int>[_allSentinel, ...DemandGenre.labels.keys];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ids.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = ids[i];
          final isAll = id == _allSentinel;
          final selected = isAll
              ? selectedGenreId == null
              : selectedGenreId == id;
          final label = isAll ? '全部' : DemandGenre.labelOf(id);
          final color = isAll ? const Color(0xFF1F2329) : DemandGenre.colorOf(id);
          final count = isAll ? totalCount : counts?[id];
          return _Chip(
            label: label,
            accent: color,
            selected: selected,
            count: count,
            onTap: () => onSelected(isAll ? null : id),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? accent : accent.withOpacity(0.12);
    final fg = selected ? Colors.white : accent;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : accent.withOpacity(0.24),
            width: 0.8,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: fg,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                height: 1.1,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withOpacity(0.28) : accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    color: fg,
                    fontWeight: FontWeight.w700,
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
