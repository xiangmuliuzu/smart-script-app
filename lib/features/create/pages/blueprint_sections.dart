import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../data/blueprint_models.dart';
import '../widgets/blueprint_visuals.dart';

/// 作品资料页的卡片与区块组件（封面卡 / 故事核心 / 世界与规则 / 人物卡 / 物品行等）。
///
/// 拆出页面的静态展示部分：页面只负责数据读取、编辑与落库。

class BlueprintBottomBar extends StatelessWidget {
  const BlueprintBottomBar({
    super.key,
    required this.confirming,
    required this.busy,
    required this.saving,
    required this.onConfirm,
    required this.onDone,
  });

  final bool confirming;
  final bool busy;
  final bool saving;
  final VoidCallback onConfirm;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: confirming
          ? FilledButton(
              onPressed: busy || saving ? null : onConfirm,
              child: Text(busy ? '正在创建作品…' : '确认，开始创作'),
            )
          : FilledButton.tonal(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: AppColors.fill,
                foregroundColor: AppColors.text1,
              ),
              child: Text(saving ? '正在保存…' : '完成'),
            ),
    );
  }
}

class BlueprintErrorBody extends StatelessWidget {
  const BlueprintErrorBody({
    super.key,required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.text2)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('重新读取')),
          ],
        ),
      ),
    );
  }
}

class BlueprintCard extends StatelessWidget {
  const BlueprintCard({
    super.key,required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}

class BlueprintSectionHeader extends StatelessWidget {
  const BlueprintSectionHeader({
    super.key,
    required this.title,
    this.hint,
    this.onEdit,
    this.onRegenerate,
    this.onAction,
    this.actionLabel,
    this.busy = false,
  });

  final String title;
  final String? hint;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onAction;
  final String? actionLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text1),
          ),
        ),
        if (hint != null)
          Text(hint!, style: const TextStyle(fontSize: 11, color: AppColors.text3)),
        if (onRegenerate != null)
          BlueprintHeaderAction(
            label: busy ? '正在整理…' : 'AI 重新整理',
            onTap: busy ? null : onRegenerate,
          ),
        if (onEdit != null)
          BlueprintHeaderAction(label: '编辑', onTap: busy ? null : onEdit),
        if (actionLabel != null && onAction != null)
          BlueprintHeaderAction(label: actionLabel!, onTap: onAction),
      ],
    );
  }
}

class BlueprintHeaderAction extends StatelessWidget {
  const BlueprintHeaderAction({
    super.key,required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.text3,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}

class BlueprintCoverCard extends StatelessWidget {
  const BlueprintCoverCard({
    super.key,
    required this.cover,
    required this.title,
    required this.tagline,
    this.onEditCover,
    this.onEditSummary,
    this.busy = false,
  });

  final String cover;
  final String title;
  final String tagline;
  final VoidCallback? onEditCover;
  final VoidCallback? onEditSummary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final display = title.trim().isEmpty ? '未命名作品' : title.trim();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BlueprintPoster(title: display, cover: cover),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.text1),
                ),
                const SizedBox(height: 6),
                Text(
                  tagline.trim().isEmpty ? '一句话简介待补充。' : tagline.trim(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, height: 1.7, color: AppColors.text2),
                ),
                const SizedBox(height: 10),
                if (onEditCover != null || onEditSummary != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (onEditCover != null)
                        BlueprintCoverButton(
                          label: cover.isEmpty ? '上传封面' : '更换封面',
                          primary: true,
                          onTap: busy ? null : onEditCover,
                        ),
                      if (onEditSummary != null)
                        BlueprintCoverButton(
                          label: '写要求',
                          onTap: busy ? null : onEditSummary,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BlueprintCoverButton extends StatelessWidget {
  const BlueprintCoverButton({
    super.key,required this.label, this.primary = false, this.onTap});

  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: primary ? Colors.white : AppColors.text3,
          ),
        ),
      ),
    );
  }
}

/// 海报：有真实封面展示图片，否则用风格化封面（渐变 + 书名竖排）。
class BlueprintPoster extends StatelessWidget {
  const BlueprintPoster({
    super.key,required this.title, required this.cover});

  final String title;
  final String cover;

  @override
  Widget build(BuildContext context) {
    const width = 104.0;
    const height = 146.0;
    final url = cover.isEmpty ? '' : AppConfig.resolveAssetUrl(cover);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? BlueprintStyledPoster(title: title)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => BlueprintStyledPoster(title: title),
              ),
      ),
    );
  }
}

class BlueprintStyledPoster extends StatelessWidget {
  const BlueprintStyledPoster({
    super.key,required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final short = title.length > 8 ? title.substring(0, 8) : title;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF20242B), Color(0xFF313A44), Color(0xFF5B6673)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            bottom: -24,
            child: Container(
              width: 110,
              height: 110,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Color(0x6BA0C8FF),
                  Color(0x00A0C8FF),
                ]),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final value in const [8.0, 16.0, 11.0, 22.0, 14.0, 19.0, 9.0])
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Container(
                      width: 2,
                      height: value,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 10,
            child: Text(
              short,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 5,
              ),
            ),
          ),
          const Positioned(
            left: 10,
            bottom: 10,
            child: Text(
              'DEEP NIGHT FM',
              style: TextStyle(
                  color: Color(0x99FFFFFF), fontSize: 8, letterSpacing: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class BlueprintStoryCoreBody extends StatelessWidget {
  const BlueprintStoryCoreBody({
    super.key,required this.story});
  final BlueprintStoryCore story;

  @override
  Widget build(BuildContext context) {
    final paragraphs = story.summary
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final details = <(String, String)>[
      if (story.coreConflict.isNotEmpty) ('核心冲突', story.coreConflict),
      if (story.narrativeStyle.isNotEmpty) ('叙事风格', story.narrativeStyle),
      if (story.contentBoundary.isNotEmpty) ('内容边界', story.contentBoundary),
      if (story.endingTone.isNotEmpty) ('结局基调', story.endingTone),
    ];
    if (paragraphs.isEmpty && details.isEmpty) {
      return const BlueprintEmptyHint('故事核心尚未整理，可以点「编辑」自己写，或让 AI 重新整理。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(paragraph,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.85, color: AppColors.text2)),
          ),
        for (final row in details)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${row.$1}　',
                  style: const TextStyle(
                      color: AppColors.text3, fontSize: 12.5),
                ),
                TextSpan(text: row.$2),
              ]),
              style: const TextStyle(
                  fontSize: 13, height: 1.75, color: AppColors.text2),
            ),
          ),
      ],
    );
  }
}

class BlueprintWorldBody extends StatelessWidget {
  const BlueprintWorldBody({
    super.key,required this.world});
  final BlueprintWorld world;

  @override
  Widget build(BuildContext context) {
    if (world.isEmpty) {
      return const BlueprintEmptyHint('世界与规则尚未整理，可以点「编辑」补充或让 AI 重新整理。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (world.setting.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(world.setting,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.85, color: AppColors.text2)),
          ),
        for (final rule in world.rules)
          BlueprintBulletText(
            rule.detail.isEmpty ? rule.name : '${rule.name}：${rule.detail}',
          ),
        for (final constraint in world.constraints) BlueprintBulletText(constraint),
      ],
    );
  }
}

class BlueprintBulletText extends StatelessWidget {
  const BlueprintBulletText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.text3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.7, color: AppColors.text2)),
          ),
        ],
      ),
    );
  }
}

class BlueprintEmptyHint extends StatelessWidget {
  const BlueprintEmptyHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, height: 1.7, color: AppColors.text3),
      ),
    );
  }
}

class BlueprintPersonCard extends StatelessWidget {
  const BlueprintPersonCard({
    super.key,
    required this.character,
    required this.index,
    this.onTap,
  });

  final BlueprintCharacter character;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CharacterPortrait(
              name: character.name,
              index: index,
              gender: character.gender,
              width: 100,
              height: 128,
              flag: 'AI 立绘',
            ),
            const SizedBox(height: 7),
            Text(
              character.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text1),
            ),
            const SizedBox(height: 2),
            Text(
              character.subtitle.isEmpty ? '身份待补充' : character.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

class BlueprintItemRow extends StatelessWidget {
  const BlueprintItemRow({
    super.key,
    required this.item,
    required this.onTap,
    this.first = false,
    this.last = false,
  });

  final BlueprintItem item;
  final VoidCallback onTap;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(top: first ? 0 : 10, bottom: last ? 0 : 10),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            ItemArtwork(icon: item.glyphIcon, name: item.name, size: 62),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text1)),
                  const SizedBox(height: 3),
                  Text(
                    item.desc.isEmpty ? (item.subtitle.isEmpty ? '暂无描述' : item.subtitle) : item.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.text3),
                  ),
                  if (item.owner.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '${item.owner} 持有',
                        style: const TextStyle(fontSize: 11, color: AppColors.text3),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}
