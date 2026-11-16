import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'drama_models.dart';

/// B 模块外部视频（漫剧）数据层（接口文档 2.8）。
///
/// 只做三件事：拼查询参数、解析 App 信封里的 `data`、把 JSON 映射成页面模型。
/// 鉴权与 Token 由 [ApiClient] 统一处理：信息流/剧集/外部视频为公开接口，
/// 进度/历史/追更/举报为私有接口，是否携带 Token 由框架决定，页面无需关心。
class DramaRepository {
  DramaRepository(this._api);

  final ApiClient _api;

  /// 短剧信息流（2.8.1，公开，分页 {total, list}）。
  Future<PagedData<DramaFeedItem>> pageFeed({
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentDramaFeed,
      query: {'page': pageNum, 'pageSize': pageSize},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取信息流失败');
    return PagedData.parse<DramaFeedItem>(data, DramaFeedItem.fromJson);
  }

  /// 剧集列表（2.8.2，公开，data={list}，按集号升序）。
  Future<List<EpisodeItem>> listEpisodes(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkEpisodes(workId),
      parser: _mapParser,
    );
    return _items(data, EpisodeItem.fromJson);
  }

  /// 剧集详情（2.8.3，公开）；不存在时后端按 404 拒绝，由 [ApiClient] 抛 [ApiException]。
  Future<EpisodeDetail> episodeDetail(int episodeId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentEpisode(episodeId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取剧集详情失败');
    return EpisodeDetail.fromJson(data);
  }

  /// 保存播放进度（2.8.4，需 App Token）；[duration] 为空表示未知总时长。
  Future<void> saveProgress(int episodeId, {required int progress, int? duration}) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeProgress(episodeId),
      data: {'progress': progress, 'duration': duration},
      parser: _mapParser,
    );
  }

  /// 获取播放进度（2.8.5，需 App Token）；无记录时 progress=0、duration=null。
  Future<PlayProgress> getProgress(int episodeId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeProgress(episodeId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取播放进度失败');
    return PlayProgress.fromJson(data);
  }

  /// 剧集解锁状态（2.8.7，需 App Token）；免费集后端直接返回已解锁。
  Future<EpisodeUnlockStatus> unlockStatus(int episodeId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeUnlockStatus(episodeId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取解锁状态失败');
    return EpisodeUnlockStatus.fromJson(data);
  }

  /// 付费解锁（2.8.8，需 App Token，幂等）；不含真实支付，后端只登记解锁记录。
  ///
  /// 免费集后端按 400 拒绝（页面不会对免费集调用）。
  Future<UnlockResult> unlockEpisode(int episodeId, {String? payType}) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeUnlock(episodeId),
      data: {if (payType != null && payType.isNotEmpty) 'payType': payType},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('解锁失败');
    return UnlockResult.fromJson(data);
  }

  /// 广告解锁（2.8.9，需 App Token，幂等）。
  Future<UnlockResult> adUnlockEpisode(int episodeId, {int? adId}) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeAdUnlock(episodeId),
      data: {if (adId != null) 'adId': adId},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('解锁失败');
    return UnlockResult.fromJson(data);
  }

  /// 播放历史（2.8.6，需 App Token，分页 {total, list}）。
  Future<PagedData<PlayHistoryItem>> pagePlayHistory({
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentPlayHistory,
      query: {'page': pageNum, 'pageSize': pageSize},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取播放历史失败');
    return PagedData.parse<PlayHistoryItem>(data, PlayHistoryItem.fromJson);
  }

  /// 追更订阅（2.8.13，需 App Token，幂等）；作品不存在/未上架时后端按 404 拒绝。
  Future<void> subscribe(int workId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentWorkSubscribe(workId),
      parser: _mapParser,
    );
  }

  /// 取消追更（2.8.13，需 App Token，幂等）；未订阅时同样成功。
  Future<void> unsubscribe(int workId) async {
    await _api.delete<Map<String, dynamic>>(
      ApiEndpoints.contentWorkSubscribe(workId),
      parser: _mapParser,
    );
  }

  /// 我的追更列表（2.8.14，需 App Token，分页 {total, list}）。
  Future<PagedData<SubscriptionItem>> pageSubscriptions({
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentSubscriptions,
      query: {'page': pageNum, 'pageSize': pageSize},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取追更列表失败');
    return PagedData.parse<SubscriptionItem>(data, SubscriptionItem.fromJson);
  }

  /// 外部视频详情（2.8.15，公开）；未上架/不存在按 404 拒绝。
  Future<DramaDetail> dramaDetail(int dramaId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentExternalDrama(dramaId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取外部视频详情失败');
    return DramaDetail.fromJson(data);
  }

  /// 找同款剧本（2.8.16，公开）；[RelatedWorkPayload.work] 未绑定或原著不可见时为 null。
  Future<RelatedWorkPayload> relatedWork(int dramaId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentExternalDramaRelatedWork(dramaId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取关联剧本失败');
    return RelatedWorkPayload.fromJson(data);
  }

  /// 提交举报（2.8.17，需 App Token）。
  ///
  /// 后端兼容 snake_case 与 camelCase，这里按模块既有风格发 camelCase。
  Future<ReportResult> report({
    required String targetType,
    required int targetId,
    required String reason,
    String? description,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentReports,
      data: {
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        if (description != null && description.isNotEmpty) 'description': description,
      },
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('提交举报失败');
    return ReportResult.fromJson(data);
  }

  /// 剧集评论列表（2.8.10，需 App Token，分页 {total, list}，含嵌套回复的平铺数据）。
  ///
  /// list 元素含 parentId：0 为一级评论，非 0 为回复，由页面按 parentId 组两层。
  Future<PagedData<CommentItem>> pageComments(
    int episodeId, {
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeComments(episodeId),
      query: {'page': pageNum, 'pageSize': pageSize},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取评论列表失败');
    return PagedData.parse<CommentItem>(data, CommentItem.fromJson);
  }

  /// 发表评论 / 回复（2.8.11，需 App Token）；返回新评论 commentId。
  ///
  /// [parentId] 为 0/null 时是一级评论；非 0 时后端校验其属于同一剧集（否则 400）。
  Future<int> createComment(
    int episodeId, {
    required String content,
    int? parentId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeCommentCreate(episodeId),
      data: {
        'content': content,
        if (parentId != null && parentId > 0) 'parentId': parentId,
      },
      parser: _mapParser,
    );
    final commentId = _intOrNull(data?['commentId']);
    if (commentId == null) throw ApiException('评论失败');
    return commentId;
  }

  /// 点赞（2.8.12，需 App Token，幂等）；返回 {liked, likeCount}。
  Future<EpisodeLikeResult> likeEpisode(int episodeId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeLike(episodeId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('点赞失败');
    return EpisodeLikeResult.fromJson(data);
  }

  /// 取消点赞（2.8.12，需 App Token，幂等）；返回 {liked:false, likeCount}。
  Future<EpisodeLikeResult> unlikeEpisode(int episodeId) async {
    final data = await _api.delete<Map<String, dynamic>>(
      ApiEndpoints.contentEpisodeLike(episodeId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('取消点赞失败');
    return EpisodeLikeResult.fromJson(data);
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static List<T> _items<T>(
    Map<String, dynamic>? data,
    T Function(Map<String, dynamic> item) itemParser,
  ) {
    final raw = data?['list'];
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map>()
        .map((e) => itemParser(Map<String, dynamic>.from(e)))
        .toList();
  }

  static int? _intOrNull(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) return int.tryParse(value);
    return null;
  }
}