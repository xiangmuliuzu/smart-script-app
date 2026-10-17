import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/config/app_config.dart';
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
          boxShadow: AppColors.cardShadow,
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

/// 抖音式竖向视频单元（漫剧信息流一页一个视频）。
///
/// 播放策略：信息流下发的 external_url 既可能是可直连的视频文件
/// （.mp4/.m3u8 等），也可能是外部网页（如抖音视频页）。
/// 直链用 video_player 内嵌播放；网页链接无法内嵌播放器，退回「在浏览器打开」，
/// 避免白屏。真实视频源的接入方案待定，此处不臆造接口，只按 URL 能力分流。
class DramaVideoPane extends StatefulWidget {
  const DramaVideoPane({
    super.key,
    required this.item,
    required this.active,
    this.onOpenDetail,
    this.onOpenRelated,
  });

  final DramaFeedItem item;

  /// 是否为当前可见页；非可见页暂停并回到片头，避免后台播放。
  final bool active;

  final VoidCallback? onOpenDetail;
  final VoidCallback? onOpenRelated;

  @override
  State<DramaVideoPane> createState() => _DramaVideoPaneState();
}

class _DramaVideoPaneState extends State<DramaVideoPane> {
  /// 可内嵌播放的直链扩展名白名单。
  static const Set<String> _directExtensions = {'mp4', 'm3u8', 'mov', 'webm', 'mkv'};

  VideoPlayerController? _controller;
  String? _error;
  bool _pausedByUser = false;

  /// 后端下发的本机地址需归一到当前环境宿主（模拟器为 10.0.2.2）；
  /// 真实外部地址不含 localhost，归一函数会原样返回。
  String get _rawUrl => widget.item.externalUrl;

  String get _playUrl => AppConfig.resolveAssetUrl(_rawUrl);

  bool get _isDirectVideo {
    final uri = Uri.tryParse(_playUrl);
    if (uri == null || !uri.hasScheme) return false;
    final path = uri.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return _directExtensions.contains(path.substring(dot + 1));
  }

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant DramaVideoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.externalUrl != widget.item.externalUrl) {
      _disposeController();
      _prepare();
    } else if (oldWidget.active != widget.active) {
      _syncPlayState();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _error = null;
    _pausedByUser = false;
  }

  Future<void> _prepare() async {
    if (_playUrl.isEmpty) {
      setState(() => _error = '暂无播放地址');
      return;
    }
    if (!_isDirectVideo) {
      setState(() => _error = '外部网页视频，无法内嵌播放');
      return;
    }
    setState(() => _error = null);
    final controller = VideoPlayerController.networkUrl(Uri.parse(_playUrl));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() {});
      _syncPlayState();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '视频加载失败');
    }
  }

  void _syncPlayState() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active) {
      if (!_pausedByUser) controller.play();
    } else {
      controller.pause();
      controller.seekTo(Duration.zero);
      _pausedByUser = false;
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
      _pausedByUser = true;
    } else {
      controller.play();
      _pausedByUser = false;
    }
    setState(() {});
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(_rawUrl);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlay,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          _buildVideo(),
          if (_showPausedIcon)
            const Center(
              child: Icon(Icons.play_arrow_rounded, size: 72, color: Colors.white70),
            ),
          if (_error == null) _buildOverlay(),
        ],
      ),
    );
  }

  bool get _showPausedIcon {
    final controller = _controller;
    if (!widget.active || controller == null || !controller.value.isInitialized) {
      return false;
    }
    return !controller.value.isPlaying;
  }

  Widget _buildVideo() {
    if (_error != null) return _buildUnplayable();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white70));
    }
    final size = controller.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.width == 0 ? 1 : size.width,
        height: size.height == 0 ? 1 : size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  /// 无法内嵌播放时的兜底：说明原因，直链以外的地址提供浏览器打开入口。
  Widget _buildUnplayable() {
    final canOpen = Uri.tryParse(_rawUrl)?.hasScheme ?? false;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.smart_display_outlined, size: 56, color: Colors.white38),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (canOpen) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                minimumSize: const Size(0, 40),
              ),
              onPressed: _openExternally,
              child: const Text('在浏览器打开'),
            ),
          ],
        ],
      ),
    );
  }

  /// 底部浮层：标题、来源/渠道标签、找同款原著与详情入口。
  Widget _buildOverlay() {
    final item = widget.item;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title.isEmpty ? '未命名视频' : item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.sourceType.isNotEmpty)
                  DramaTag(text: item.sourceType, color: Colors.white),
                if (item.channelName.isNotEmpty)
                  Text(
                    item.channelName,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.hasRelatedWork)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      minimumSize: const Size(0, 38),
                    ),
                    onPressed: widget.onOpenRelated,
                    child: const Text('找同款原著'),
                  ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: widget.onOpenDetail,
                  child: const Text('查看详情'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}