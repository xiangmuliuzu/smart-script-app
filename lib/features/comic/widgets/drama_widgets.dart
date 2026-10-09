import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/drama_models.dart';

/// B 模块外部视频（漫剧）公共组件。
///
/// 抽离原因：信息流卡片、剧集行、追更行、播放历史行在多个页面复用同一套
/// 「封面占位 / 标题 / 元信息 / 状态标记」结构，按组件复用原则统一封装，
/// 避免页面级复制粘贴导致样式漂移。
///
/// 封面说明：外部视频/剧集的封面在库端为文件ID（cover_file_id）或外链，
/// 无通用文件表可反查 URL，故统一走占位块，不做网络取图。

/// 外部视频封面占位块（渐变底 + 播放图标）。
class DramaCoverPlaceholder extends StatelessWidget {
  const DramaCoverPlaceholder({
    super.key,
    this.width = 120,
    this.height = 68,
    this.radius = AppRadius.rSmall,
    this.iconSize = 28,
  });

  final double width;
  final double height;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryTint, AppColors.cyanTint],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.play_circle_outline,
          size: iconSize,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// 信息流卡片（2.8.1）。
class DramaFeedCard extends StatelessWidget {
  const DramaFeedCard({super.key, required this.item, this.onTap});

  final DramaFeedItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.r),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DramaCoverPlaceholder(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? '未命名视频' : item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.sourceType.isNotEmpty)
                        DramaTag(text: item.sourceType, color: AppColors.primary),
                      if (item.channelName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.channelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.text3),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (item.hasRelatedWork)
                    const DramaTag(text: '可找同款原著', color: AppColors.success)
                  else
                    const Text(
                      '暂无关联原著',
                      style: TextStyle(fontSize: 12, color: AppColors.text3),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 剧集行（2.8.2）。列表不下发播放地址，点击进入播放页取详情。
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({super.key, required this.episode, this.onTap});

  final EpisodeItem episode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (episode.episodeNo > 0) '第 ${episode.episodeNo} 集',
      if (episode.durationLabel.isNotEmpty) episode.durationLabel,
      if (episode.playCount > 0) '${episode.playCount} 次播放',
    ].join(' · ');
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
            const DramaCoverPlaceholder(width: 64, height: 40, iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title.isEmpty ? '第 ${episode.episodeNo} 集' : episode.title,
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
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              episode.payLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: episode.isFree ? AppColors.success : AppColors.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放历史行（2.8.6）。无进度时只展示当前集。
class PlayHistoryTile extends StatelessWidget {
  const PlayHistoryTile({super.key, required this.item, this.onTap});

  final PlayHistoryItem item;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DramaCoverPlaceholder(width: 64, height: 40, iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.workTitle.isEmpty ? item.episodeTitle : item.workTitle,
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
                    item.progressLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                  if (item.playTime != null && item.playTime!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.playTime!,
                      style: const TextStyle(fontSize: 12, color: AppColors.text3),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.play_circle_outline, size: 22, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// 追更行（2.8.14）。[onOpen] 打开作品详情，[onCancel] 取消追更（页面已确认）。
class SubscriptionTile extends StatelessWidget {
  const SubscriptionTile({
    super.key,
    required this.item,
    this.onOpen,
    this.onCancel,
  });

  final SubscriptionItem item;
  final VoidCallback? onOpen;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (item.authorName.isNotEmpty) item.authorName,
      if (item.episodeCount > 0) '共 ${item.episodeCount} 集',
      if (item.price > 0) '¥${item.price.toStringAsFixed(2)}',
    ].join(' · ');
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DramaCoverPlaceholder(width: 56, height: 76, iconSize: 24),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    meta.isEmpty ? '未知作者' : meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                  const SizedBox(height: 6),
                  if (item.createdAt != null && item.createdAt!.isNotEmpty)
                    Text(
                      '追更于 ${item.createdAt}',
                      style: const TextStyle(fontSize: 12, color: AppColors.text3),
                    ),
                ],
              ),
            ),
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                child: const Text('取消追更', style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 小标签（来源类型 / 关联原著标记等）。
class DramaTag extends StatelessWidget {
  const DramaTag({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}