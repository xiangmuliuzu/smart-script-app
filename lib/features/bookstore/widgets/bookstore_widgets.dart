import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../data/bookstore_models.dart';

/// 作品封面：无图/加载失败时统一回落占位，避免书城出现破图。
/// 地址经 [AppConfig.resolveAssetUrl] 归一，兼容相对路径与各开发环境的 host 差异。
class WorkCover extends StatelessWidget {
  const WorkCover({
    super.key,
    required this.url,
    this.title = '',
    this.width = 56,
    this.height = 76,
    this.radius = AppRadius.rSmall,
  });

  final String url;
  final String title;
  final double width;
  final double height;
  final double radius;

  /// 默认封面渐变色板：按书名 hash 取色，同一本书颜色稳定。
  static const List<List<Color>> _palettes = [
    [Color(0xFF667EEA), Color(0xFF764BA2)], // 紫蓝
    [Color(0xFF2193B0), Color(0xFF4A00E0)], // 蓝紫
    [Color(0xFFF2994A), Color(0xFFD35C5C)], // 橙红
    [Color(0xFF11998E), Color(0xFF38EF7D)], // 青绿
    [Color(0xFFEE9CA7), Color(0xFFFFDDE1)], // 粉红
    [Color(0xFF355C7D), Color(0xFF6C5B7B)], // 深蓝紫
    [Color(0xFFE53935), Color(0xFFB71C3C)], // 红
    [Color(0xFF1A2980), Color(0xFF26D0CE)], // 深海蓝
  ];

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
                AppConfig.resolveAssetUrl(url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
      ),
    );
  }

  Widget _placeholder() {
    // 有书名：渐变底 + 书名居中，像正式封面
    if (title.trim().isNotEmpty) {
      final palette = _palettes[title.hashCode.abs() % _palettes.length];
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette,
          ),
        ),
        padding: const EdgeInsets.all(10),
        alignment: Alignment.center,
        child: Text(
          title.trim(),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
        ),
      );
    }
    // 无书名：原图标占位
    return Container(
      color: AppColors.primaryTint,
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book_outlined, color: AppColors.primary, size: 20),
    );
  }
}

/// 分类 + 标签胶囊组（作品卡片、详情页共用）。
///
/// [genreName] 为分类（题材），用主色描边突出；[tags] 为标签，用中性填充。
/// 两者均可在传入对应回调后点击，跳转「按该分类/标签筛选的作品列表」；
/// 回调为空时仅作展示。分类与标签都为空时整块不占位。
class WorkTagChips extends StatelessWidget {
  const WorkTagChips({
    super.key,
    this.genreName = '',
    this.tags = const <TagItem>[],
    this.onGenreTap,
    this.onTagTap,
    this.spacing = 6,
    this.fontSize = 11,
  });

  final String genreName;
  final List<TagItem> tags;

  /// 分类点击（传入则分类胶囊可点）。
  final VoidCallback? onGenreTap;

  /// 标签点击（传入则标签胶囊可点）。
  final void Function(TagItem tag)? onTagTap;
  final double spacing;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (genreName.isEmpty && tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        if (genreName.isNotEmpty)
          _WorkChip(
            label: genreName,
            color: AppColors.primary,
            background: AppColors.primaryTint,
            fontSize: fontSize,
            onTap: onGenreTap,
          ),
        for (final tag in tags)
          _WorkChip(
            label: tag.tagName,
            color: AppColors.text2,
            background: AppColors.fill,
            fontSize: fontSize,
            onTap: onTagTap == null ? null : () => onTagTap!(tag),
          ),
      ],
    );
  }
}

class _WorkChip extends StatelessWidget {
  const _WorkChip({
    required this.label,
    required this.color,
    required this.background,
    required this.fontSize,
    this.onTap,
  });

  final String label;
  final Color color;
  final Color background;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: fontSize, color: color)),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// 作品列表行（书城推荐流、作品列表页共用）。
class WorkListTile extends StatelessWidget {
  const WorkListTile({
    super.key,
    required this.work,
    this.onTap,
    this.trailing,
    this.progressText,
    this.showDivider = false,
  });

  final BookItem work;
  final VoidCallback? onTap;

  /// 行尾扩展动作（如收藏列表的「取消收藏」）；为空时只展示价格。
  final Widget? trailing;

  /// 额外的阅读进度行（仅书架列表传入，如「读到第 3 章 · 时间」）；为空则不占位。
  final String? progressText;

  /// 是否绘制底部分隔线；首页卡片内连续排列时传 true。
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: showDivider
              ? const Border(bottom: BorderSide(color: AppColors.divider, width: 0.5))
              : null,
        ),
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
                  if (work.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    WorkTagChips(tags: work.tags),
                  ],
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
    this.showDivider = true,
  });

  final RankingItem item;
  final String scoreText;
  final VoidCallback? onTap;

  /// 是否为该行绘制底部分隔线；卡片内最后一行传 false。
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isTop3 = item.rankNo <= 3;
    final Color rankColor = switch (item.rankNo) {
      1 => const Color(0xFFFFB300),
      2 => const Color(0xFF9E9E9E),
      3 => const Color(0xFFCD7F32),
      _ => AppColors.text3,
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: BoxDecoration(
          // 首页卡片内与卡片同色；独立榜单页同样使用本行，保持白底。
          color: AppColors.card,
          // 卡片内最后一行的分隔线交给调用方决定，这里只画行间线。
          border: showDivider
              ? const Border(bottom: BorderSide(color: AppColors.divider, width: 0.5))
              : null,
        ),
        child: Row(
          children: [
            // 排名数字：前三名用金银铜色，其余灰色
            SizedBox(
              width: 28,
              child: Text(
                '${item.rankNo}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isTop3 ? 22 : 18,
                  fontWeight: FontWeight.w800,
                  color: rankColor,
                  fontStyle: isTop3 ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            const SizedBox(width: 12),
            WorkCover(url: item.cover, width: 46, height: 62),
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isTop3 ? AppColors.primary : AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区块标题（首页与榜单页共用：左标题 + 右「更多」）。
/// 白色圆角卡片容器：统一白底、12 圆角与轻阴影（首页各区块复用）。
///
/// 与贴边的通栏列表不同，卡片左右留 14，在页面冰蓝渐变背景上形成浮层，
/// 和「我的」页等卡片式页面保持一致。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(14, 12, 14, 0),
  });

  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.r)),
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}

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

/// 下拉式筛选条（分类 / 标签等选项较多的筛选用）。
///
/// 与 [FilterChipBar] 的区别：以「筛选名 + 当前选中项 + 下拉箭头」按钮呈现，
/// 点击弹出底部弹窗列出全部选项，避免选项过多时必须横向滚动才能选到。
class FilterDropdownBar extends StatelessWidget {
  const FilterDropdownBar({super.key, required this.filters});

  final List<FilterDropdownFilter> filters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _FilterDropdownButton(filter: filters[i])),
          ],
        ],
      ),
    );
  }
}

class _FilterDropdownButton extends StatelessWidget {
  const _FilterDropdownButton({required this.filter});

  final FilterDropdownFilter filter;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Text(filter.label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                filter.valueText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final option = await showModalBottomSheet<FilterDropdownOption>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '选择${filter.label}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filter.options.length,
                  itemBuilder: (context, index) {
                    final item = filter.options[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 14,
                          color: item.selected ? AppColors.primary : AppColors.text1,
                        ),
                      ),
                      trailing: item.selected
                          ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (option != null) option.onTap();
  }
}

class FilterDropdownFilter {
  const FilterDropdownFilter({
    required this.label,
    required this.valueText,
    required this.options,
  });

  /// 筛选名（如「分类」「标签」）。
  final String label;

  /// 当前选中项展示文案（如「全部类型」「都市」）。
  final String valueText;

  final List<FilterDropdownOption> options;
}

class FilterDropdownOption {
  const FilterDropdownOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
}