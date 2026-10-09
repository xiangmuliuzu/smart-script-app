import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../user_center/data/paged_data.dart';
import 'drama_models.dart';
import 'drama_repository.dart';

/// B 模块外部视频（漫剧）依赖注入（复用框架层网络栈，不新建 Dio）。

final dramaRepositoryProvider = Provider<DramaRepository>(
  (ref) => DramaRepository(ref.watch(apiClientProvider)),
);

/// 外部视频详情（2.8.15，公开）；未上架/不存在时抛 [ApiException]，页面展示错误态。
final dramaDetailProvider = FutureProvider.autoDispose.family<DramaDetail, int>(
  (ref, dramaId) => ref.watch(dramaRepositoryProvider).dramaDetail(dramaId),
);

/// 剧集列表（2.8.2，公开）；按集号升序，无剧集时为空列表。
final episodeListProvider = FutureProvider.autoDispose.family<List<EpisodeItem>, int>(
  (ref, workId) => ref.watch(dramaRepositoryProvider).listEpisodes(workId),
);

/// 剧集详情（2.8.3，公开）；含播放地址。
final episodeDetailProvider = FutureProvider.autoDispose.family<EpisodeDetail, int>(
  (ref, episodeId) => ref.watch(dramaRepositoryProvider).episodeDetail(episodeId),
);

/// 播放进度（2.8.5，需 App Token）。
///
/// 播放页是公开页，游客不 watch（进度区块隐藏），避免为必然 401 的请求往返。
final playProgressProvider = FutureProvider.autoDispose.family<PlayProgress, int>(
  (ref, episodeId) => ref.watch(dramaRepositoryProvider).getProgress(episodeId),
);

/// 剧集解锁状态（2.8.7，需 App Token）。
///
/// 仅在付费集上 watch：免费集由剧集详情即可判定，无需请求。
final episodeUnlockStatusProvider = FutureProvider.autoDispose.family<EpisodeUnlockStatus, int>(
  (ref, episodeId) => ref.watch(dramaRepositoryProvider).unlockStatus(episodeId),
);

/// 找同款剧本（2.8.16，公开）；work 为 null 表示未绑定或原著不可见。
final relatedWorkProvider = FutureProvider.autoDispose.family<RelatedWorkPayload, int>(
  (ref, dramaId) => ref.watch(dramaRepositoryProvider).relatedWork(dramaId),
);

/// 剧集评论（2.8.10，需 App Token）；取第一页（每页上限 50），页面按 parentId 组两层。
///
/// 后端列表为「一级评论 + 回复」的平铺数据，一级与其回复可能跨页；
/// 一期只取首页，页面据此展示，不额外翻页。
final episodeCommentsProvider = FutureProvider.autoDispose.family<PagedData<CommentItem>, int>(
  (ref, episodeId) => ref.watch(dramaRepositoryProvider).pageComments(
        episodeId,
        pageNum: 1,
        pageSize: 50,
      ),
);