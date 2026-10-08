import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/bookstore_models.dart';

/// 作品封面：无图/加载失败时统一回落占位，避免书城出现破图。
class WorkCover extends StatelessWidget {
  const WorkCover({
    super.key,
    required this.url,
    this.width = 56,
    this.height = 76,
    this.radius = AppRadius.rSmall,
  });

  final String url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? _placeholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.primaryTint,
        alignment: Alignment.center,
        child: const Icon(Icons.menu_book_outlined, color: AppColors.primary, size: 20),
      );
}

/// 作品列表行（书城推荐流、作品列表页共用）。
class WorkListTile extends StatelessWidget {
  const WorkListTile({
    super.key,
    required this.work,
    this.onTap,
    this.trailing,
    this.progressText,
  });

  final BookItem work;
  final VoidCallback? onTap;

  /// 行尾扩展动作（如收藏列表的「取消收藏」）；为空时只展示价格。
  final Widget? trailing;

  /// 额外的阅读进度行（仅书架列表传入，如「读到第 3 章 · 时间」）；为空则不占位。
  final String? progressText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorkCover(url: work.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.title.isEmpty ? '未命名作品' : work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _subtitle(work),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${work.wordCount} 字 · ${work.episodeCount} 集 · 评分 ${work.rating.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                  if (progressText != null && progressText!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      progressText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              work.priceLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: work.isFree ? AppColors.success : AppColors.warning,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }

  static String _subtitle(BookItem work) {
    final parts = <String>[
      if (work.authorName.isNotEmpty) work.authorName,
      if (work.genreName.isNotEmpty) work.genreName,
    ];
    return parts.isEmpty ? '未知作者' : parts.join(' · ');
  }
}

/// 榜单行（首页榜单预览与榜单页共用）。
///
/// [scoreText] 由调用方按榜单类型格式化（人数类取整、评分保留一位小数）。
class RankingRow extends StatelessWidget {
  const RankingRow({
    super.key,
    required this.item,
    required this.scoreText,
    this.onTap,
  });

  final RankingItem item;
  final String scoreText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            _RankBadge(rankNo: item.rankNo),
            const SizedBox(width: 12),
            WorkCover(url: item.cover, width: 44, height: 60),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? '未命名作品' : item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.authorName.isNotEmpty) item.authorName,
                      if (item.genreName.isNotEmpty) item.genreName,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              scoreText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 名次徽标：前三名用语义色区分，其余走辅助色。
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rankNo});

  final int rankNo;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (rankNo) {
      1 => AppColors.warning,
      2 => AppColors.text2,
      3 => AppColors.success,
      _ => AppColors.text3,
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$rankNo',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// 区块标题（首页与榜单页共用：左标题 + 右「更多」）。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.onMore});

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const Spacer(),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              child: const Text('更多', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

/// 可点选的胶囊筛选条（排序 / 标签 / 榜单类型共用）。
class FilterChipBar extends StatelessWidget {
  const FilterChipBar({super.key, required this.items});

  final List<FilterChipItem> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: item.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: item.selected ? AppColors.primaryTint : AppColors.fill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.selected ? AppColors.primary : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.selected ? AppColors.primary : AppColors.text2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FilterChipItem {
  const FilterChipItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
}