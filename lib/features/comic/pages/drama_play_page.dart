import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/drama_models.dart';
import '../data/drama_providers.dart';
import '../widgets/drama_widgets.dart';

/// 短剧播放页（B 模块，接口文档 2.8.2 剧集列表 / 2.8.3 剧集详情 /
/// 2.8.4 保存进度 / 2.8.5 获取进度 / 2.8.10 评论列表 / 2.8.11 发表评论 / 2.8.12 点赞）。
///
/// 受登录守卫保护（[RoutePath.dramaPlay] 前缀）：进度与历史均归属当前身份，
/// 未登录不进入本页，避免为必然 401 的请求往返。
///
/// 播放方式：剧集播放地址为站外链接（videoUrl），由系统浏览器/外部播放器打开，
/// 不做站内内嵌播放。因此无法回传真实播放位置，见 [PlayProgress] 的上报说明。
class DramaPlayPage extends ConsumerStatefulWidget {
  const DramaPlayPage({super.key, required this.workId, this.episodeId});

  final int workId;

  /// 指定要播放的集；为空时默认选中第一集。
  final int? episodeId;

  @override
  ConsumerState<DramaPlayPage> createState() => _DramaPlayPageState();
}

class _DramaPlayPageState extends ConsumerState<DramaPlayPage> {
  int? _selectedId;
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.episodeId;
  }

  /// 选中集：优先用当前选中（须在当前作品剧集内），否则回落第一集。
  int _resolveSelected(List<EpisodeItem> list) {
    final current = _selectedId;
    if (current != null && list.any((e) => e.episodeId == current)) return current;
    return list.first.episodeId;
  }

  /// 打开站外播放地址，并登记「已观看本集」（2.8.4 同时刷新播放历史）。
  ///
  /// 进度值沿用已记录进度（无记录为 0），不用臆测值覆盖历史记录；
  /// 站外播放无法回传真实播放位置，本动作只保证该集出现在播放历史中。
  Future<void> _play(EpisodeDetail detail) async {
    final messenger = ScaffoldMessenger.of(context);
    if (detail.videoUrl.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('该集暂无播放地址')));
      return;
    }
    final uri = Uri.tryParse(detail.videoUrl);
    if (uri == null) {
      messenger.showSnackBar(const SnackBar(content: Text('播放地址无效')));
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('无法打开播放地址')));
      return;
    }
    if (_registering) return;
    setState(() => _registering = true);
    try {
      final current = ref.read(playProgressProvider(detail.episodeId)).valueOrNull;
      await ref.read(dramaRepositoryProvider).saveProgress(
            detail.episodeId,
            progress: current?.progress ?? 0,
            duration: detail.duration > 0 ? detail.duration : current?.duration,
          );
      ref.invalidate(playProgressProvider(detail.episodeId));
    } catch (_) {
      // 播放已成功打开，进度登记失败不阻断用户观看，静默处理。
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodes = ref.watch(episodeListProvider(widget.workId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('短剧播放')),
      body: episodes.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (e, __) => ErrorView(
          message: e is ApiException ? e.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(episodeListProvider(widget.workId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyView(message: '该作品暂无短剧剧集', icon: Icons.movie_outlined);
          }
          final selectedId = _resolveSelected(list);
          // 剧集列表与评论同处一个滚动视图：播放页信息密度低，分栏滚动反而割裂。
          return ListView(
            children: [
              _PlayerCard(
                episodeId: selectedId,
                onPlay: _play,
                registering: _registering,
              ),
              const Divider(height: 1, color: AppColors.divider),
              for (final episode in list)
                Container(
                  color: episode.episodeId == selectedId
                      ? AppColors.primaryTint
                      : Colors.transparent,
                  child: EpisodeTile(
                    episode: episode,
                    onTap: () => setState(() => _selectedId = episode.episodeId),
                  ),
                ),
              const Divider(height: 1, color: AppColors.divider),
              _CommentSection(episodeId: selectedId),
            ],
          );
        },
      ),
    );
  }
}

/// 播放卡：选中集信息 + 上次进度 + 播放按钮。
class _PlayerCard extends ConsumerWidget {
  const _PlayerCard({
    required this.episodeId,
    required this.onPlay,
    required this.registering,
  });

  final int episodeId;
  final Future<void> Function(EpisodeDetail detail) onPlay;
  final bool registering;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(episodeDetailProvider(episodeId));
    final progress = ref.watch(playProgressProvider(episodeId));
    return detail.when(
      loading: () => const SizedBox(
        height: 160,
        child: LoadingView(message: '加载中'),
      ),
      error: (e, __) => SizedBox(
        height: 160,
        child: ErrorView(
          message: e is ApiException ? e.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(episodeDetailProvider(episodeId)),
        ),
      ),
      data: (item) {
        final saved = progress.valueOrNull;
        return Container(
          color: AppColors.card,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DramaCoverPlaceholder(width: 120, height: 72, iconSize: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title.isEmpty ? '第 ${item.episodeNo} 集' : item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (item.episodeNo > 0) '第 ${item.episodeNo} 集',
                            item.payLabel,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _progressText(saved, item),
                style: const TextStyle(fontSize: 12, color: AppColors.primary),
              ),
              const SizedBox(height: 12),
              _PlayAction(
                episodeId: episodeId,
                detail: item,
                saved: saved,
                registering: registering,
                onPlay: onPlay,
              ),
              const SizedBox(height: 6),
              const Text(
                '播放由外部应用提供；打开即登记本集为「已观看」，可在播放历史中查看。',
                style: TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _progressText(PlayProgress? saved, EpisodeDetail item) {
    if (saved == null || saved.progress <= 0) return '暂无观看记录';
    final total = saved.duration ?? item.duration;
    if (total <= 0) return '上次记录：已看 ${saved.progress} 秒';
    return '上次记录：已看 ${saved.progress} 秒 / 共 $total 秒';
  }
}

/// 播放动作区（2.8.7 解锁状态 / 2.8.8 付费解锁 / 2.8.9 广告解锁）。
///
/// 免费集直接展示播放按钮；付费集先查解锁状态：已解锁展示播放按钮，
/// 未解锁展示解锁入口（付费 / 看广告），解锁成功后刷新状态即可播放。
class _PlayAction extends ConsumerStatefulWidget {
  const _PlayAction({
    required this.episodeId,
    required this.detail,
    required this.saved,
    required this.registering,
    required this.onPlay,
  });

  final int episodeId;
  final EpisodeDetail detail;
  final PlayProgress? saved;
  final bool registering;
  final Future<void> Function(EpisodeDetail detail) onPlay;

  @override
  ConsumerState<_PlayAction> createState() => _PlayActionState();
}

class _PlayActionState extends ConsumerState<_PlayAction> {
  bool _unlocking = false;

  @override
  Widget build(BuildContext context) {
    if (widget.detail.isFree) return _playButton();
    final status = ref.watch(episodeUnlockStatusProvider(widget.episodeId));
    return status.when(
      loading: () => const Text(
        '正在获取解锁状态…',
        style: TextStyle(fontSize: 13, color: AppColors.text3),
      ),
      error: (e, __) => Row(
        children: [
          Expanded(
            child: Text(
              e is ApiException ? e.message : '解锁状态获取失败',
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(episodeUnlockStatusProvider(widget.episodeId)),
            child: const Text('重试'),
          ),
        ],
      ),
      data: (status) =>
          status.isUnlocked ? _playButton(unlocked: true) : _unlockButtons(),
    );
  }

  /// 播放按钮；[unlocked] 为 true 时补一行「已解锁」提示。
  Widget _playButton({bool unlocked = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: widget.registering ? null : () => widget.onPlay(widget.detail),
          icon: const Icon(Icons.play_arrow, size: 20),
          label: Text(widget.saved != null && widget.saved!.progress > 0 ? '继续播放' : '播放'),
        ),
        if (unlocked) ...[
          const SizedBox(height: 6),
          const Text('本集已解锁', style: TextStyle(fontSize: 12, color: AppColors.text3)),
        ],
      ],
    );
  }

  /// 付费未解锁集的解锁入口。
  Widget _unlockButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _unlocking ? null : () => _unlock(byAd: false),
          icon: const Icon(Icons.lock_open, size: 20),
          label: Text('付费解锁 ${widget.detail.payLabel}'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _unlocking ? null : () => _unlock(byAd: true),
          icon: const Icon(Icons.ondemand_video, size: 20),
          label: const Text('看广告解锁'),
        ),
      ],
    );
  }

  /// 执行解锁（付费 / 广告），成功后刷新解锁状态，播放按钮随之出现。
  Future<void> _unlock({required bool byAd}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _unlocking = true);
    try {
      final repo = ref.read(dramaRepositoryProvider);
      final result = byAd
          ? await repo.adUnlockEpisode(widget.episodeId)
          : await repo.unlockEpisode(widget.episodeId);
      messenger.showSnackBar(
        SnackBar(content: Text(result.message.isEmpty ? '解锁成功' : result.message)),
      );
      ref.invalidate(episodeUnlockStatusProvider(widget.episodeId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('解锁失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }
}

/// 评论与点赞区块（2.8.10 列表 / 2.8.11 发表 / 2.8.12 点赞）。
///
/// 列表是「一级评论 + 回复」的平铺数据，这里按 parentId 组两层；
/// 回复只针对一级评论（与后端 parentExistsInEpisode 的校验口径一致）。
/// 一期只取首页，超出时提示仅展示最新若干条。
class _CommentSection extends ConsumerStatefulWidget {
  const _CommentSection({required this.episodeId});

  final int episodeId;

  @override
  ConsumerState<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends ConsumerState<_CommentSection> {
  final TextEditingController _inputCtrl = TextEditingController();

  /// 当前回复目标（一级评论）；为空时发一级评论。
  CommentItem? _replyTo;
  bool _sending = false;

  /// 与 sys_comment.content varchar(500) 一致。
  static const int _contentMax = 500;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) {
      _toast('请输入评论内容');
      return;
    }
    if (text.length > _contentMax) {
      _toast('评论不能超过 $_contentMax 字');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(dramaRepositoryProvider).createComment(
            widget.episodeId,
            content: text,
            parentId: _replyTo?.commentId,
          );
      _inputCtrl.clear();
      setState(() => _replyTo = null);
      ref.invalidate(episodeCommentsProvider(widget.episodeId));
      _toast('评论成功');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('评论失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(episodeCommentsProvider(widget.episodeId));
    final data = comments.valueOrNull;
    final list = data?.list ?? const <CommentItem>[];
    final topLevel = list.where((c) => c.isTopLevel).toList();
    final replies = <int, List<CommentItem>>{};
    for (final item in list) {
      if (item.isTopLevel) continue;
      replies.putIfAbsent(item.parentId, () => <CommentItem>[]).add(item);
    }
    final total = data?.total ?? 0;
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '评论 $total',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const Spacer(),
              _EpisodeLikeButton(episodeId: widget.episodeId),
            ],
          ),
          if (comments.isLoading && data == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LoadingView(message: '加载评论中'),
            ),
          if (comments.hasError && data == null)
            ErrorView(
              message: comments.error is ApiException
                  ? (comments.error as ApiException).message
                  : '评论加载失败',
              onRetry: () => ref.invalidate(episodeCommentsProvider(widget.episodeId)),
            ),
          if (data != null && topLevel.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '还没有评论，来说两句吧',
                style: TextStyle(fontSize: 13, color: AppColors.text3),
              ),
            ),
          for (final item in topLevel) ...[
            _CommentTile(item: item, onReply: () => setState(() => _replyTo = item)),
            for (final reply in replies[item.commentId] ?? const <CommentItem>[])
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: _CommentTile(item: reply),
              ),
          ],
          if (data != null && total > list.length) ...[
            const SizedBox(height: 4),
            Text(
              '仅展示最新 ${list.length} 条评论',
              style: const TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          ],
          const SizedBox(height: 12),
          if (_replyTo != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '正在回复 ${_replyTo!.nickName.isEmpty ? '该用户' : _replyTo!.nickName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _replyTo = null),
                  child: const Text('取消', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: _contentMax,
                  decoration: InputDecoration(
                    hintText: _replyTo == null ? '说点什么…' : '回复该评论',
                    counterText: '',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                // 主题的 minimumSize 为 Size.fromHeight(44)（最小宽度无限），
                // 在 Row 中会收到「紧约束无限宽」而崩溃，此处覆盖为有限最小宽度。
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单条评论（一级或回复）。
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.item, this.onReply});

  final CommentItem item;

  /// 仅一级评论提供「回复」入口；为 null 时不展示。
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = item.avatar.startsWith('http') ? item.avatar : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryTint,
            backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
            child: avatarUrl == null
                ? Text(
                    item.nickName.isEmpty ? '客' : item.nickName.substring(0, 1),
                    style: const TextStyle(fontSize: 12, color: AppColors.primary),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nickName.isEmpty ? '匿名用户' : item.nickName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(item.content, style: const TextStyle(fontSize: 14, color: AppColors.text1)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (item.createdAt != null && item.createdAt!.isNotEmpty)
                      Text(
                        item.createdAt!,
                        style: const TextStyle(fontSize: 12, color: AppColors.text3),
                      ),
                    if (onReply != null) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onReply,
                        child: const Text(
                          '回复',
                          style: TextStyle(fontSize: 12, color: AppColors.primary),
                        ),
                      ),
                    ],
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

/// 剧集点赞按钮（2.8.12，幂等）。
///
/// 接口只提供点赞/取消点赞，没有「查询点赞态」，故初始状态按未点赞展示；
/// 首次点击即与后端对齐（重复点赞后端幂等且回报真实态），之后按返回值切换。
class _EpisodeLikeButton extends ConsumerStatefulWidget {
  const _EpisodeLikeButton({required this.episodeId});

  final int episodeId;

  @override
  ConsumerState<_EpisodeLikeButton> createState() => _EpisodeLikeButtonState();
}

class _EpisodeLikeButtonState extends ConsumerState<_EpisodeLikeButton> {
  bool _busy = false;
  bool _liked = false;

  /// 点赞数；未交互前后端未下发，保持为空不显示数字。
  int? _count;

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final repo = ref.read(dramaRepositoryProvider);
      final result = _liked
          ? await repo.unlikeEpisode(widget.episodeId)
          : await repo.likeEpisode(widget.episodeId);
      if (!mounted) return;
      setState(() {
        _liked = result.liked;
        _count = result.likeCount;
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _liked ? AppColors.danger : AppColors.text3;
    return TextButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: Icon(_liked ? Icons.favorite : Icons.favorite_border, size: 18, color: color),
      label: Text(
        _count == null ? '点赞' : '$_count',
        style: TextStyle(fontSize: 13, color: color),
      ),
    );
  }
}