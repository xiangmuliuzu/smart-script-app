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
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/write',
      data: <String, dynamic>{
        'prompt': prompt,
        if (type != null && type.isNotEmpty) 'type': type,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    if (data == null) throw ApiException('AI 写作失败');
    return AiWriteResult.fromJson(data);
  }

  /// AI 写作（流式，SSE 打字机输出）。
  ///
  /// [onDelta] 逐块回调内容增量；后端流成功结束后才落记录并扣减次数，
  /// 中途失败/断线不落库不扣次数。返回完整内容与记录ID。
  Future<AiWriteResult> writeStream({
    required String prompt,
    String? type,
    required void Function(String delta) onDelta,
  }) async {
    final body = await _api.postStream(
      '$_contentPrefix/write/stream',
      data: <String, dynamic>{
        'prompt': prompt,
        if (type != null && type.isNotEmpty) 'type': type,
      },
      receiveTimeout: _aiReceiveTimeout,
    );
    return await _consumeSseWrite(body.stream, onDelta);
  }

  /// AI 润色：{content, style} → {content, recordId}。
  Future<AiWriteResult> polish({
    required String content,
    String? style,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/polish',
      data: <String, dynamic>{
        'content': content,
        if (style != null && style.isNotEmpty) 'style': style,
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
    required void Function(String delta) onDelta,
  }) async {
    final body = await _api.postStream(
      '$_contentPrefix/polish/stream',
      data: <String, dynamic>{
        'content': content,
        if (style != null && style.isNotEmpty) 'style': style,
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
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '$_contentPrefix/outline',
      data: <String, dynamic>{
        if (inspiration != null && inspiration.isNotEmpty)
          'inspiration': inspiration,
        if (genre != null && genre.isNotEmpty) 'genre': genre,
        if (style != null && style.isNotEmpty) 'style': style,
      },
      receiveTimeout: _aiReceiveTimeout,
      parser: _map,
    );
    if (data == null) throw ApiException('AI 大纲生成失败');
    return AiOutlineResult.fromJson(data);
  }

  /// AI 大纲（流式，SSE 打字机输出）。
  ///
  /// 流式期间 [onDelta] 收到可读文本；兼容历史 JSON 大纲，完成事件后返回结果。
  Future<AiOutlineResult> outlineStream({
    String? inspiration,
    String? genre,
    String? style,
    required void Function(String delta) onDelta,
  }) async {
    final body = await _api.postStream(
      '$_contentPrefix/outline/stream',
      data: <String, dynamic>{
        if (inspiration != null && inspiration.isNotEmpty)
          'inspiration': inspiration,
        if (genre != null && genre.isNotEmpty) 'genre': genre,
        if (style != null && style.isNotEmpty) 'style': style,
      },
      receiveTimeout: _aiReceiveTimeout,
    );
    final buffer = StringBuffer();
    int quotaUsed = 0;
    var requestNo = '';
    var completed = false;
    await consumeSseEvents(body.stream, (event) {
      if (event.payload?['done'] == true) {
        completed = true;
        quotaUsed = event.intValue('quotaUsed');
        requestNo = event.text('requestNo');
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
    );
  }

  /// 消费写作/润色 SSE 流：逐块回调 delta，done 后返回 {content, recordId}。
  Future<AiWriteResult> _consumeSseWrite(
    Stream<Uint8List> stream,
    void Function(String delta) onDelta,
  ) async {
    final buffer = StringBuffer();
    int recordId = 0;
    var completed = false;
    await consumeSseEvents(stream, (event) {
      if (event.payload?['done'] == true) {
        completed = true;
        recordId = event.intValue('recordId');
      } else {
        final delta = event.text('delta');
        if (delta.isNotEmpty) { buffer.write(delta); onDelta(delta); }
      }
    });
    if (!completed) throw ApiException('生成中断，已保留收到的内容，请重试');
    if (buffer.toString().trim().isEmpty) throw ApiException('本次未返回生成内容，请重试');
    return AiWriteResult(content: buffer.toString(), recordId: recordId);
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
  Future<AiPageResult<AiWriteRecord>> writeRecords({
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '$_contentPrefix/write-records',
      query: {'page': page, 'pageSize': pageSize},
      parser: _map,
    );
    if (data == null) throw ApiException('AI 写作记录加载失败');
    return AiPageResult.fromJson(data, AiWriteRecord.fromJson);
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((key, value) => MapEntry('$key', value));
    throw ApiException('AI 数据响应无效');
  }
}
