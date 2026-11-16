import 'dart:convert';
import 'dart:typed_data';


import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'ai_models.dart';
import 'ai_sse_parser.dart';

/// AI 创作业务仓库（App 端 E 模块）。
///
/// 所有写操作带幂等键（后端幂等防重复扣减/补偿/兑换）。
class AiRepository {
  AiRepository(this._api);

  final ApiClient _api;

  static const _prefix = '/ai/quota';

  /// AI 生成（大纲/写作/润色）耗时可超过全局 30s 接收超时，单独放长到 120s。
  static const _aiReceiveTimeout = Duration(seconds: 120);

  /// 查询 AI 机会余额与最近流水。
  Future<AiQuotaBalance> balance(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '$_prefix/balance',
      query: {'userId': userId},
      parser: _map,
    );
    if (data == null) throw ApiException('机会余额加载失败');
    return AiQuotaBalance.fromJson(data);
  }

  /// AI 调用消耗机会（预扣；返回最新可用次数）。
  Future<int> consume({
    required int userId,
    required String capability,
    int quotaCost = 1,
    int? workId,
    required String idempotencyKey,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_prefix/consume',
      data: <String, dynamic>{
        'userId': userId,
        'capability': capability,
        'quotaCost': quotaCost,
        if (workId != null) 'workId': workId,
        'idempotencyKey': idempotencyKey,
      },
      parser: _map,
    );
    return (data?['balance'] as num?)?.toInt() ?? 0;
  }

  /// AI 调用失败补偿机会（幂等；返回最新可用次数）。
  Future<int> refund({
    required int userId,
    int amount = 1,
    int? workId,
    required String idempotencyKey,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_prefix/refund',
      data: <String, dynamic>{
        'userId': userId,
        'amount': amount,
        if (workId != null) 'workId': workId,
        'idempotencyKey': idempotencyKey,
      },
      parser: _map,
    );
    return (data?['balance'] as num?)?.toInt() ?? 0;
  }

  /// 积分兑换 AI 机会（只能积分换次数；返回最新可用次数）。
  Future<int> exchange({
    required int userId,
    required int points,
    required String idempotencyKey,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_prefix/exchange',
      data: <String, dynamic>{
        'userId': userId,
        'points': points,
        'idempotencyKey': idempotencyKey,
      },
      parser: _map,
    );
    return (data?['balance'] as num?)?.toInt() ?? 0;
  }


  // ================================================================
  // AI 创作（大纲/写作/润色），对接 /api/v1/content/ai/*
  // ================================================================

  static const _contentPrefix = '/content/ai';

  /// AI 写作：{prompt, type} → {content, recordId}。
  Future<AiWriteResult> write({
    required String prompt,
    String? type,
    int? skillId,
    String? model,
    int? workId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/write',
      data: <String, dynamic>{
        'prompt': prompt,
        if (type != null && type.isNotEmpty) 'type': type,
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
        if (workId != null) 'workId': workId,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    if (data == null) throw ApiException('AI 续写失败');
    return AiWriteResult.fromJson(data);
  }

  /// AI 写作（流式，SSE 打字机输出）。
  ///
  /// [onDelta] 逐块回调内容增量；后端流成功结束后才落记录并扣减次数，
  /// 中途失败/断线不落库不扣次数。返回完整内容与记录ID。
  Future<AiWriteResult> writeStream({
    required String prompt,
    String? type,
    int? skillId,
    String? model,
    int? workId,
    required void Function(String delta) onDelta,
  }) async {
    final body = await _api.postStream(
      '$_contentPrefix/write/stream',
      data: <String, dynamic>{
        'prompt': prompt,
        if (type != null && type.isNotEmpty) 'type': type,
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
        if (workId != null) 'workId': workId,
      },
      receiveTimeout: _aiReceiveTimeout,
    );
    return await _consumeSseWrite(body.stream, onDelta);
  }

  /// 本章摘要 + 台账回写（方案 2）：正文定稿后单独一次调用。
  ///
  /// 后端读正文（[content] 可为刚插入、尚未保存的全文）产出「本章摘要 + 七类台账更新」，
  /// 写 sys_work_chapter.summary 并合并 sys_work_ledger；正文不发生任何改动。
  Future<Map<String, dynamic>> summarizeChapter({
    required int workId,
    required int chapterId,
    required String content,
    String? model,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/chapter-summary',
      data: <String, dynamic>{
        'workId': workId,
        'chapterId': chapterId,
        'content': content,
        if (model != null && model.isNotEmpty) 'model': model,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    return data ?? <String, dynamic>{};
  }

  /// 每集验收（5 项判定：人物/因果/连续性/伏笔/结构，≥4 项通过）：只判定不改正文。
  Future<Map<String, dynamic>> reviewChapter({
    required int workId,
    required int chapterId,
    required String content,
    String? model,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/chapter-review',
      data: <String, dynamic>{
        'workId': workId,
        'chapterId': chapterId,
        'content': content,
        if (model != null && model.isNotEmpty) 'model': model,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    return data ?? <String, dynamic>{};
  }

  /// 卷级状态快照：每 10 集一卷，只存当前值（人物处境/卷末悬念/未回收伏笔/物品归属）。
  Future<Map<String, dynamic>> buildVolumeSnapshot({
    required int workId,
    required int volumeNo,
    String? model,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/volume-snapshot',
      data: <String, dynamic>{
        'workId': workId,
        'volumeNo': volumeNo,
        if (model != null && model.isNotEmpty) 'model': model,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    return data ?? <String, dynamic>{};
  }

  /// AI 润色：{content, style} → {content, recordId}。
  Future<AiWriteResult> polish({
    required String content,
    String? style,
    int? skillId,
    String? model,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/polish',
      data: <String, dynamic>{
        'content': content,
        if (style != null && style.isNotEmpty) 'style': style,
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    if (data == null) throw ApiException('AI 润色失败');
    return AiWriteResult.fromJson(data);
  }

  /// AI 润色（流式，SSE 打字机输出）。
  Future<AiWriteResult> polishStream({
    required String content,
    String? style,
    int? skillId,
    String? model,
    required void Function(String delta) onDelta,
  }) async {
    final body = await _api.postStream(
      '$_contentPrefix/polish/stream',
      data: <String, dynamic>{
        'content': content,
        if (style != null && style.isNotEmpty) 'style': style,
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
      },
      receiveTimeout: _aiReceiveTimeout,
    );
    return await _consumeSseWrite(body.stream, onDelta);
  }

  /// AI 大纲：{inspiration, genre, style} → {outline, requestNo, quotaUsed}。
  Future<AiOutlineResult> outline({
    String? inspiration,
    String? genre,
    String? style,
    int? skillId,
    String? model,
    int? workId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/outline',
      data: <String, dynamic>{
        if (inspiration != null && inspiration.isNotEmpty)
          'inspiration': inspiration,
        if (genre != null && genre.isNotEmpty) 'genre': genre,
        if (style != null && style.isNotEmpty) 'style': style,
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
        if (workId != null) 'workId': workId,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    if (data == null) throw ApiException('AI 剧本生成失败');
    return AiOutlineResult.fromJson(data);
  }

  /// AI 大纲（流式，SSE 打字机输出）。
  ///
  /// 流式期间 [onDelta] 收到可读文本；兼容历史 JSON 大纲，完成事件后返回结果。
  Future<AiOutlineResult> outlineStream({
    String? inspiration,
    String? genre,
    String? style,
    int? skillId,
    String? model,
    int? workId,
    required void Function(String delta) onDelta,
  }) async {
    final body = await _api.postStream(
      '$_contentPrefix/outline/stream',
      data: <String, dynamic>{
        if (inspiration != null && inspiration.isNotEmpty)
          'inspiration': inspiration,
        if (genre != null && genre.isNotEmpty) 'genre': genre,
        if (style != null && style.isNotEmpty) 'style': style,
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
        if (workId != null) 'workId': workId,
      },
      receiveTimeout: _aiReceiveTimeout,
    );
    final buffer = StringBuffer();
    int quotaUsed = 0;
    var requestNo = '';
    int recordId = 0;
    var completed = false;
    await consumeSseEvents(body.stream, (event) {
      if (event.payload?['done'] == true) {
        completed = true;
        quotaUsed = event.intValue('quotaUsed');
        requestNo = event.text('requestNo');
        recordId = event.intValue('recordId');
        // 大纲分批生成后以 done 下发的规整全文为准（delta 可能在集号处缺换行）。
        final full = event.text('content');
        if (full.isNotEmpty) { buffer.clear(); buffer.write(full); }
      } else {
        final delta = event.text('delta');
        if (delta.isNotEmpty) { buffer.write(delta); onDelta(delta); }
      }
    });
    if (!completed) throw ApiException('生成中断，已保留收到的内容，请重试');
    if (buffer.toString().trim().isEmpty) throw ApiException('本次未返回生成内容，请重试');
    final raw = buffer.toString();
    return AiOutlineResult(
      outline: _tryParseOutline(raw),
      requestNo: requestNo,
      quotaUsed: quotaUsed,
      recordId: recordId,
    );
  }

  /// 作品创作台账（跨端共享：PC 端编辑保存，App 端读取后注入续写）。
  ///
  /// 后端 `GET /api/v1/content/works/{workId}/ledger`；作品尚无台账时返回仅含 workId 的空对象。
  Future<Map<String, String>> workLedger(int workId) async {
    if (workId <= 0) return const {};
    final data = await _api.get<Map<String, dynamic>>(
      '/content/works/$workId/ledger',
      parser: _map,
    );
    if (data == null) return const {};
    const keys = <String>[
      'storySummary',
      'characters',
      'relations',
      'foreshadow',
      'timeline',
      'items',
      'threads',
    ];
    return {
      for (final key in keys) key: (data[key] ?? '').toString().trim(),
    };
  }

  /// 卷级状态快照（每 10 集一卷）：返回 {卷号: 快照}；未生成时为空。
  ///
  /// 后端 `GET /api/v1/content/works/{workId}/volumes`；续写时注入「本卷 + 上卷」，
  /// 替代整份台账，避免集数越多注入的越是第 1 集旧状态。
  Future<Map<int, String>> workVolumes(int workId) async {
    if (workId <= 0) return const {};
    final data = await _api.get<List<dynamic>>(
      '/content/works/$workId/volumes',
      parser: (raw) {
        if (raw is List) return raw;
        if (raw is Map) {
          final list = raw['list'] ?? raw['rows'] ?? raw['data'];
          if (list is List) return list;
        }
        return const <dynamic>[];
      },
    );
    if (data == null) return const {};
    final result = <int, String>{};
    for (final item in data) {
      if (item is! Map) continue;
      final no = int.tryParse('${item['volumeNo'] ?? ''}');
      final snapshot = (item['snapshot'] ?? '').toString().trim();
      if (no != null && snapshot.isNotEmpty) result[no] = snapshot;
    }
    return result;
  }

  /// 导演(skill) 列表（管理员端上传配置，App 端选择注入）。
  Future<List<AiSkill>> listSkills() async {
    final data = await _api.get<List<dynamic>>(
      '$_contentPrefix/skills',
      parser: (raw) {
        if (raw is List) return raw;
        if (raw is Map) {
          final list = raw['list'] ?? raw['rows'];
          if (list is List) return list;
        }
        return const <dynamic>[];
      },
    );
    if (data == null) return const [];
    return data
        .map((e) => AiSkill.fromJson(
            e is Map ? Map<String, dynamic>.from(e) : const {}))
        .toList();
  }

  /// AI 分镜：{script, style} → {content, recordId}（完成的分镜可直接出售）。
  Future<AiWriteResult> storyboard({
    required String script,
    String? style,
    int? skillId,
    String? model,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/storyboard',
      data: <String, dynamic>{
        'script': script,
        if (style != null && style.isNotEmpty) 'style': style,
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    if (data == null) throw ApiException('AI 分镜生成失败');
    return AiWriteResult.fromJson(data);
  }

  /// AI 分镜（流式，SSE 打字机输出）。
  Future<AiWriteResult> storyboardStream({
    required String script,
    String? style,
    int? skillId,
    String? model,
    required void Function(String delta) onDelta,
  }) async {
    final body = await _api.postStream(
      '$_contentPrefix/storyboard/stream',
      data: <String, dynamic>{
        'script': script,
        if (style != null && style.isNotEmpty) 'style': style,
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
      },
      receiveTimeout: _aiReceiveTimeout,
    );
    return await _consumeSseWrite(body.stream, onDelta);
  }

  /// 渠道模型列表（管理员端配置，App 端「模型选择」下拉数据源）。
  Future<List<AiChannel>> listModels() async {
    final data = await _api.get<List<dynamic>>(
      '$_contentPrefix/models',
      parser: (raw) {
        if (raw is List) return raw;
        if (raw is Map) {
          final list = raw['list'] ?? raw['rows'];
          if (list is List) return list;
        }
        return const <dynamic>[];
      },
    );
    if (data == null) return const [];
    return data
        .map((e) => AiChannel.fromJson(
            e is Map ? Map<String, dynamic>.from(e) : const {}))
        .toList();
  }

  /// 消费写作/润色 SSE 流：逐块回调 delta，done 后返回 {content, recordId}。
  Future<AiWriteResult> _consumeSseWrite(
    Stream<Uint8List> stream,
    void Function(String delta) onDelta,
  ) async {
    final buffer = StringBuffer();
    int recordId = 0;
    var completed = false;
    var truncated = false;
    await consumeSseEvents(stream, (event) {
      if (event.payload?['done'] == true) {
        completed = true;
        recordId = event.intValue('recordId');
        truncated = event.payload?['truncated'] == true;
      } else {
        final delta = event.text('delta');
        if (delta.isNotEmpty) { buffer.write(delta); onDelta(delta); }
      }
    });
    if (!completed) throw ApiException('生成中断，已保留收到的内容，请重试');
    if (buffer.toString().trim().isEmpty) throw ApiException('本次未返回生成内容，请重试');
    return AiWriteResult(
      content: buffer.toString(),
      recordId: recordId,
      truncated: truncated,
    );
  }

  /// 流式大纲：把完整 JSON 文本解析为对象；非 JSON 则保留可读文本。
  static dynamic _tryParseOutline(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return raw;
    }
  }

  /// AI 写作记录（分页）。
  /// 删除本人的若干条 AI 记录（批量；后端按当前登录身份过滤归属）。
  ///
  /// 返回实际删除条数；一次创作的大纲与章节记录会在同一请求里一起删除。
  Future<int> deleteWriteRecords(List<int> recordIds) async {
    final data = await _api.delete<dynamic>(
      '$_contentPrefix/write-records',
      data: <String, dynamic>{'recordIds': recordIds},
      parser: (json) => json,
    );
    if (data is num) return data.toInt();
    if (data is Map) {
      final value = data['deleted'] ?? data['count'];
      return value is num ? value.toInt() : recordIds.length;
    }
    return recordIds.isEmpty ? 0 : recordIds.length;
  }

  Future<AiPageResult<AiWriteRecord>> writeRecords({
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '$_contentPrefix/write-records',
      query: {'page': page, 'pageSize': pageSize},
      parser: _map,
    );
    if (data == null) throw ApiException('AI 续写记录加载失败');
    return AiPageResult.fromJson(data, AiWriteRecord.fromJson);
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((key, value) => MapEntry('$key', value));
    throw ApiException('服务暂时不可用，请稍后再试');
  }
}
