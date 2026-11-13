import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'trade_models.dart';

/// 任务广场（需求悬赏）数据层。
class DemandRepository {
  DemandRepository(this._api);

  final ApiClient _api;

  // ==================== 征集任务 ====================

  /// 任务列表（分页）。
  /// [mine] 为空时为任务广场（仅可接取：后端强制 status=open）；
  /// claimed=我接取的（返回全部状态，仅本人可见）。
  Future<PagedData<DemandTask>> pageDemands({
    String? status,
    int? genreId,
    String? taskType,
    String? keyword,
    String? mine,
    String? sortBy,
    String? order,
    int? budgetMinFen,
    int? budgetMaxFen,
    int? episodesMin,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.demandList,
      query: _compact({
        'status': status,
        'genreId': genreId,
        'taskType': taskType,
        'keyword': keyword,
        'mine': mine,
        'sortBy': sortBy,
        'order': order,
        'budgetMin': budgetMinFen,
        'budgetMax': budgetMaxFen,
        'episodesMin': episodesMin,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取任务列表失败');
    return PagedData.parse<DemandTask>(data, DemandTask.fromJson);
  }

  /// 任务广场轻量统计（原始 map，由 provider 解析为 [DemandStats]）。
  /// 返回含 availableCount / prizePoolFen(分) / todayNewCount / genreCounts:[{genreId,count}]。
  /// 均为"公开可接单"口径（status=open），与广场列表一致，与登录无关。
  Future<Map<String, dynamic>> demandStats() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.demandStats,
      parser: _mapParser,
    );
    return data ?? const <String, dynamic>{};
  }

  /// 任务详情。
  Future<DemandTask> demandDetail(int demandId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.demandDetail(demandId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取任务详情失败');
    return DemandTask.fromJson(data);
  }

  /// 抢单（创作者先到先得接单，无需押金）。
  Future<DemandTask> claimDemand(int demandId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandClaim(demandId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('接单失败');
    return DemandTask.fromJson(data);
  }

  /// 创建/获取任务会话（创作者发起，与接单任务的平台运营沟通），返回 sessionId。
  Future<int> createDemandChatSession(int demandId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandChatSession(demandId),
      parser: _mapParser,
    );
    final sessionId = (data?['sessionId'] as num?)?.toInt();
    if (sessionId == null) throw ApiException('创建任务会话失败');
    return sessionId;
  }

  // ==================== 验收轮次 ====================

  /// 获取任务验收轮次列表。
  Future<List<DemandStage>> demandStages(int demandId) async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.demandStages(demandId),
      parser: (raw) => raw is List ? raw : <dynamic>[],
    );
    if (data == null) return [];
    return data
        .whereType<Map>()
        .map((e) => DemandStage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 可交付作品列表（本人、非已上架售卖）。
  Future<List<DeliverableWork>> deliverableWorks() async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.demandDeliverableWorks,
      parser: (raw) => raw is List ? raw : <dynamic>[],
    );
    if (data == null) return [];
    return data
        .whereType<Map>()
        .map((e) => DeliverableWork.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 查看任务的源剧本（分镜类任务）：作品源给全本正文，文件源给下载地址。
  /// 任何登录用户可读——潜在接单者要先评估剧本再决定接单。
  Future<SourceScript> sourceScript(int demandId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.demandSourceScript(demandId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('源剧本加载失败');
    return SourceScript.fromMap(data);
  }

  /// 创作者提交本轮交付物。
  ///
  /// 剧本类任务 [workId] 必填（本人未上架作品）；分镜类（storyboard）可只交文件链接与说明，
  /// 此时后端跳过 AI 剧本审核，直接进入平台人工验收。
  Future<DemandStage> deliverStage(int demandId, int stageId, {
    int? workId,
    String? deliverableDesc,
    String? deliverableUrl,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandStageDeliver(demandId, stageId),
      data: _compact({
        'workId': workId,
        'deliverableDesc': deliverableDesc,
        'deliverableUrl': deliverableUrl,
      }),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('提交交付物失败');
    return DemandStage.fromJson(data);
  }

  /// 创作者对活动轮发起延时申请（每次新增一条历史记录，既往申请不覆盖；days+hours 必须大于 0）。
  Future<DemandStage> requestExtend(int demandId, int stageId, {
    int days = 0,
    int hours = 0,
    String? reason,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandStageExtendRequest(demandId, stageId),
      data: _compact({
        'days': days,
        'hours': hours,
        'reason': reason,
      }),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('发起延时申请失败');
    return DemandStage.fromJson(data);
  }

  /// 整单延时记录（申请延时 + 运营自主延时，含各轮，每条带 stageOrder），按发生时间倒序；仅任务双方可查。
  Future<List<DemandExtendApply>> extendHistory(int demandId) async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.demandExtendHistory(demandId),
      parser: (raw) => raw is List ? raw : <dynamic>[],
    );
    if (data == null) return [];
    return data
        .whereType<Map>()
        .map((e) => DemandExtendApply.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ==================== helpers ====================

  static Map<String, dynamic> _compact(Map<String, dynamic> map) {
    return Map.fromEntries(map.entries.where((e) => e.value != null));
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw == null) return <String, dynamic>{};
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}
