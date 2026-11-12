import 'package:dio/dio.dart';

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
  /// [mine] 为空时为任务广场（仅可接取：后端强制 open ∧ escrowed）；
  /// published=我发布的，claimed=我接取的（两者返回全部状态，仅本人可见）。
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
  /// 均为"公开可接单"口径（status=open ∧ escrow=escrowed），与广场列表一致，与登录无关。
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

  /// 发布任务。[taskType] 取 script / script_storyboard / storyboard；
  /// storyboard 必须同时提供源剧本（[sourceWorkId] 选本人作品 或 [sourceScriptUrl] 上传文件，可并存）。
  Future<DemandTask> createDemand({
    required String title,
    int? genreId,
    int? budget, // 分
    String? deadline, // yyyy-MM-dd
    String? requirement,
    String? tags,
    int? totalEpisodes,
    int? durationHours,
    String? taskType,
    int? sourceWorkId,
    String? sourceScriptUrl,
    String? sourceScriptName,
    List<Map<String, dynamic>>? stages, // [{stageOrder, episodeTo, amount(元)}]
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandCreate,
      data: _compact({
        'title': title,
        'genreId': genreId,
        'budget': budget,
        'deadline': deadline,
        'requirement': requirement,
        'tags': tags,
        'totalEpisodes': totalEpisodes,
        'durationHours': durationHours,
        'taskType': taskType,
        'sourceWorkId': sourceWorkId,
        'sourceScriptUrl': sourceScriptUrl,
        'sourceScriptName': sourceScriptName,
        'stages': stages,
      }),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('发布任务失败');
    return DemandTask.fromJson(data);
  }

  /// 关闭征集。
  Future<void> closeDemand(int demandId) async {
    await _api.put<dynamic>(ApiEndpoints.demandClose(demandId));
  }

  /// 编辑任务（仅发布者、仅未托管未接单可改）。参数与 [createDemand] 一致。
  Future<DemandTask> updateDemand({
    required int demandId,
    required String title,
    int? genreId,
    int? budget, // 分
    String? deadline, // yyyy-MM-dd
    String? requirement,
    String? tags,
    int? totalEpisodes,
    int? durationHours,
    String? taskType,
    int? sourceWorkId,
    String? sourceScriptUrl,
    String? sourceScriptName,
    List<Map<String, dynamic>>? stages, // [{stageOrder, episodeTo, amount(元), durationDays, durationHours}]
  }) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.demandUpdate(demandId),
      data: _compact({
        'title': title,
        'genreId': genreId,
        'budget': budget,
        'deadline': deadline,
        'requirement': requirement,
        'tags': tags,
        'totalEpisodes': totalEpisodes,
        'durationHours': durationHours,
        'taskType': taskType,
        'sourceWorkId': sourceWorkId,
        'sourceScriptUrl': sourceScriptUrl,
        'sourceScriptName': sourceScriptName,
        'stages': stages,
      }),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('保存修改失败');
    return DemandTask.fromJson(data);
  }

  /// 抢单（创作者先到先得接单）。
  Future<DemandTask> claimDemand(int demandId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandClaim(demandId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('接单失败');
    return DemandTask.fromJson(data);
  }

  /// 创建/获取任务会话（发布者 ↔ 创作者），返回 sessionId。
  /// 发布者发起传 [targetUserId]（要沟通的创作者）；创作者发起不传。
  Future<int> createDemandChatSession(int demandId, {int? targetUserId}) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandChatSession(demandId),
      query: targetUserId != null ? {'targetUserId': '$targetUserId'} : null,
      parser: _mapParser,
    );
    final sessionId = (data?['sessionId'] as num?)?.toInt();
    if (sessionId == null) throw ApiException('创建任务会话失败');
    return sessionId;
  }

  // ==================== 支付宝沙箱入账（托管/押金） ====================

  /// 发起托管付款（发布者）：返回 {qrCode, amount(分), ...}。
  /// [refresh] 为 true 时服务端换新商户单号重新预下单，用于收款码失效后手动换码。
  Future<Map<String, dynamic>> payEscrow(int demandId, {bool refresh = false}) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandPayEscrow(demandId),
      query: <String, dynamic>{'refresh': refresh},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取托管支付二维码失败');
    // 旧码其实已被扫付时，服务端就地结算并直接返回结果，此时没有 qrCode
    if (data['paid'] == true) return data;
    if (data['qrCode'] is! String) throw ApiException('获取托管支付二维码失败');
    return data;
  }

  /// 确认托管付款：服务端向支付宝查单，成功则置 escrowed。
  /// 返回 {paid, closed?}，closed 为 true 表示支付宝侧该单已关闭、当前收款码失效。
  Future<Map<String, dynamic>> confirmEscrow(int demandId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandPayEscrowConfirm(demandId),
      parser: _mapParser,
    );
    return data ?? const <String, dynamic>{'paid': false};
  }

  /// 开发直通托管（点一下即完成）：不走沙箱查单，服务端直接把托管置为 escrowed。
  /// 沙箱密钥未接入时用于打通"发布→托管→广场曝光"；失败（如开关未开）抛 ApiException。
  Future<void> devPassEscrow(int demandId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandEscrowDevPass(demandId),
      parser: _mapParser,
    );
  }

  /// 开发直通押金（点一下即付款接单）：与托管直通同开关，服务端记账押金并原子完成抢单。
  /// 失败（如已被他人接走/开关未开）抛 ApiException，后端 message 带原因。
  Future<void> devPassDeposit(int demandId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandPayDepositDevPass(demandId),
      parser: _mapParser,
    );
  }

  /// 发起押金付款（创作者）：返回 {qrCode, amount(分), ...}。
  /// [refresh] 为 true 且当前用户就是该收款记录的付款人时，服务端换新单号重出码。
  Future<Map<String, dynamic>> payDeposit(int demandId, {bool refresh = false}) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandPayDeposit(demandId),
      query: <String, dynamic>{'refresh': refresh},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取押金支付二维码失败');
    if (data['paid'] == true) return data;
    if (data['qrCode'] is! String) throw ApiException('获取押金支付二维码失败');
    return data;
  }

  /// 确认押金付款：查单成功后服务端自动接单，返回 {paid, claimed, closed?, reason?}（抢单落败时带 reason）。
  Future<Map<String, dynamic>> confirmDeposit(int demandId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.demandPayDepositConfirm(demandId),
      parser: _mapParser,
    );
    return data ?? const <String, dynamic>{'paid': false};
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

  /// 发布分镜任务时可选的源剧本作品（本人作品，不限上下架状态）。
  Future<List<DeliverableWork>> sourceWorks() async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.demandSourceWorks,
      parser: (raw) => raw is List ? raw : <dynamic>[],
    );
    if (data == null) return [];
    return data
        .whereType<Map>()
        .map((e) => DeliverableWork.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 上传源剧本文件（发布分镜任务用）。返回 {url, fileName}，url 为相对路径。
  Future<Map<String, dynamic>> uploadSourceScript({
    required List<int> bytes,
    required String fileName,
    String? contentType,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName, contentType: contentType == null ? null : DioMediaType.parse(contentType)),
    });
    final data = await _api.upload<Map<String, dynamic>>(
      ApiEndpoints.demandUploadScript,
      formData: formData,
      parser: _mapParser,
    );
    if (data == null || (data['url'] as String? ?? '').isEmpty) {
      throw ApiException('源剧本上传失败');
    }
    return data;
  }

  /// 查看任务的源剧本（分镜类任务）：作品源给全本正文，文件源给下载地址。
  /// 任何登录用户可读——潜在接单者要先评估剧本再决定付押金。
  Future<SourceScript> sourceScript(int demandId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.demandSourceScript(demandId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('源剧本加载失败');
    return SourceScript.fromMap(data);
  }

  /// 验收查阅：发布者查看某轮交付的作品。
  ///
  /// 交付作品一定未上架，读者接口（content 域）取不到；正文只下发本轮 episodeTo 内的集，
  /// 之后的章节只有标题、readable=false。仅该任务发布者可调，非发布者后端会拒。
  Future<StageDeliverableView> stageDeliverableView(int demandId, int stageId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.demandStageDeliverableWork(demandId, stageId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('交付内容加载失败');
    return StageDeliverableView.fromJson(data);
  }

  /// 创作者提交本轮交付物。
  ///
  /// 剧本类任务 [workId] 必填（本人未上架作品）；分镜类（storyboard）可只交文件链接与说明，
  /// 此时后端跳过 AI 剧本审核，直接进入发布者人工验收。
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

  /// 买方审核轮次。
  Future<DemandStage> reviewStage(int demandId, int stageId, {
    required bool approved,
    String? rejectReason,
  }) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.demandStageReview(demandId, stageId),
      data: _compact({
        'approved': approved,
        'rejectReason': rejectReason,
      }),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('审核轮次失败');
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

  /// 发布者处理延时申请：只处理当前待处理那条（处理完保留为历史），同意则截止同步顺延，不同意仅落决定。
  Future<DemandStage> decideExtend(int demandId, int stageId, {required bool approved}) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.demandStageExtendDecision(demandId, stageId),
      data: {'approved': approved},
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('处理延时申请失败');
    return DemandStage.fromJson(data);
  }

  /// 发布者自主延时：不经申请直接顺延活动轮截止（同时落一条延时记录）。
  Future<DemandStage> selfExtend(int demandId, int stageId, {
    int days = 0,
    int hours = 0,
  }) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.demandStageExtend(demandId, stageId),
      data: _compact({'days': days, 'hours': hours}),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('延时失败');
    return DemandStage.fromJson(data);
  }

  /// 整单延时记录（申请延时 + 自主延时，含各轮，每条带 stageOrder），按发生时间倒序；仅任务双方可查。
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
