import 'dart:typed_data';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../ai/data/ai_sse_parser.dart';
import 'author_work_models.dart';
import 'author_work_repository.dart';
import 'blueprint_models.dart';
import 'chapter_meta_models.dart';
import 'create_repository.dart';

/// v3 作品资料 / 章节资料数据层（真实对接后端，不落任何本地权威副本）。
///
/// 接口：
///   POST /content/ai/blueprint/stream          SSE：event:stage（story/world/characters/items/outline）
///                                              + data:{delta} + data:{done,sessionId,blueprint}
///   POST /content/ai/blueprint/regenerate      SSE：同上（done 携带最新 blueprint）
///   POST /content/ai/blueprint/{sessionId}/confirm → {workId}
///   GET  /content/ai/blueprint/{sessionId}     → 待确认会话
///   GET  /content/works/{workId}/blueprint     → 作品已确认资料（无会话时 null）
///   GET  /content/works/{workId}/ledger        → 台账十类
///   PUT  /content/works/{workId}/ledger        → 台账整份保存（未传字段保留）
///   POST /content/ai/chapter-draft/stream      SSE：done.draft
///   POST /content/ai/chapter-meta              → 本章资料（AI 整理并落库）
///   GET  /content/works/{workId}/chapter-meta  → {章号: 本章资料}
///   PUT  /content/works/{workId}/chapter-meta/{chapterNo} → 单章资料
///
/// 注意：后端**没有**「作品资料写接口」。作者手动修改作品资料时，
/// 结构化字段会被转换成台账十类后写 [`saveLedger`]（与 PC 创作者端共用同一份数据），
/// 封面 / 简介写作品基本信息（A 套 `PUT /users/me/works/{workId}`）。
class BlueprintRepository {
  BlueprintRepository(this._api, this._works, this._create);

  final ApiClient _api;
  final AuthorWorkRepository _works;
  final CreateRepository _create;

  /// 资料生成 / 重生成可能持续数分钟（后端等 AI 完整输出），流式超时单独放宽。
  static const Duration _streamTimeout = Duration(minutes: 10);

  /// 非流式的本章资料整理同样可能超时，与 PC 端一致放宽到 10 分钟。
  static const Duration _longTimeout = Duration(minutes: 10);

  // ================================================================
  // 作品资料
  // ================================================================

  /// 生成作品资料（SSE）。返回 done 事件里下发的会话。
  ///
  /// [onStage] 收到 `event:stage` 的 stage 名；[onDelta] 收到资料 JSON 的文本增量
  /// （仅用于「正在生成」的字节计数，不直接渲染——资料是结构化 JSON，确认页展示结构化结果）。
  Future<BlueprintSession> generate({
    required String title,
    required String inspiration,
    String? genre,
    String? prompt,
    int? skillId,
    String? model,
    int? sessionId,
    void Function(String stage)? onStage,
    void Function(String delta)? onDelta,
  }) async {
    final body = await _api.postStream(
      ApiEndpoints.aiBlueprintStream,
      data: <String, dynamic>{
        'title': title,
        'inspiration': inspiration,
        if (genre != null && genre.trim().isNotEmpty) 'genre': genre.trim(),
        if (prompt != null && prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
        if (skillId != null) 'skillId': skillId,
        if (model != null && model.isNotEmpty) 'model': model,
        if (sessionId != null && sessionId > 0) 'sessionId': sessionId,
      },
      receiveTimeout: _streamTimeout,
    );
    return _consumeBlueprintStream(body.stream, onStage: onStage, onDelta: onDelta);
  }

  /// 重新整理作品资料（单项 / 按 key / 全部）。返回最新会话。
  Future<BlueprintSession> regenerate({
    required int sessionId,
    required String section,
    String? key,
    String? instruction,
    String? model,
    int? skillId,
    void Function(String stage)? onStage,
    void Function(String delta)? onDelta,
  }) async {
    final body = await _api.postStream(
      ApiEndpoints.aiBlueprintRegenerate,
      data: <String, dynamic>{
        'sessionId': sessionId,
        'section': section,
        if (key != null && key.isNotEmpty) 'key': key,
        if (instruction != null && instruction.trim().isNotEmpty)
          'instruction': instruction.trim(),
        if (model != null && model.isNotEmpty) 'model': model,
        if (skillId != null) 'skillId': skillId,
      },
      receiveTimeout: _streamTimeout,
    );
    return _consumeBlueprintStream(body.stream, onStage: onStage, onDelta: onDelta);
  }

  /// 待确认会话详情。
  Future<BlueprintSession> session(int sessionId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.aiBlueprintSession(sessionId),
      parser: _mapParser,
    );
    if (data == null || data['blueprint'] == null) {
      throw ApiException('该会话没有可确认的作品资料');
    }
    return BlueprintSession.fromJson(data);
  }

  /// 确认资料并创建作品，返回 workId。
  Future<int> confirm(int sessionId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.aiBlueprintConfirm(sessionId),
      parser: _mapParser,
    );
    final workId = data?['workId'];
    final parsed = workId is num ? workId.toInt() : int.tryParse('${workId ?? ''}');
    if (parsed == null || parsed <= 0) throw ApiException('作品创建失败，响应缺少作品编号');
    return parsed;
  }

  /// 作品已确认的资料会话；作品没有资料会话（如旧作品 / 手工建的作品）时返回 null。
  Future<BlueprintSession?> workSession(int workId) async {
    if (workId <= 0) return null;
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkBlueprint(workId),
      parser: _mapParser,
    );
    if (data == null || data['blueprint'] == null) return null;
    return BlueprintSession.fromJson(data);
  }

  /// 作品创作台账。
  Future<WorkLedger> ledger(int workId) async {
    if (workId <= 0) return const WorkLedger();
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkLedger(workId),
      parser: _mapParser,
    );
    return WorkLedger.fromJson(data);
  }

  /// 保存台账（整份覆盖写入；后端对未传字段保留原值）。
  Future<void> saveLedger(int workId, WorkLedger ledger) async {
    if (workId <= 0) return;
    await _api.put<Map<String, dynamic>>(
      ApiEndpoints.contentWorkLedger(workId),
      data: <String, dynamic>{...ledger.toFields()},
      parser: _mapParser,
    );
  }

  /// 保存结构化作品资料：转换成台账十类后整份写入。
  Future<void> saveBlueprint(int workId, StoryBlueprint blueprint) =>
      saveLedger(workId, blueprintToLedger(blueprint));

  /// 上传本地封面（`POST /content/upload`，type=cover），返回可落库的 url。
  Future<String> uploadCover({
    required List<int> bytes,
    required String filename,
  }) =>
      _create.uploadCoverBytes(bytes: bytes, filename: filename);

  /// 更新作品简介 / 封面（作品基本信息，A 套）。
  Future<void> updateWorkBase(
    int workId, {
    String? summary,
    String? cover,
  }) =>
      _works.updateWorkBase(workId, summary: summary, cover: cover);

  /// 读取作品 + 台账并合成「作品资料」视图（没有任何资料时返回空资料）。
  ///
  /// 规则：以已确认的资料会话为准；没有资料会话时按台账宽松还原（[ledgerToBlueprint]）；
  /// 最后用作品简介对齐故事核心（作品简介是作者在「设置」里维护的权威值）。
  Future<StoryBlueprint> loadBlueprint(
    int workId, {
    required AuthorWorkItem? work,
    WorkLedger? ledger,
  }) async {
    BlueprintSession? session;
    try {
      session = await workSession(workId);
    } catch (_) {
      // 老作品/网络抖动读不到资料会话时按台账兜底，不阻塞资料页。
      session = null;
    }
    var resolvedLedger = ledger;
    if (resolvedLedger == null) {
      try {
        resolvedLedger = await this.ledger(workId);
      } catch (_) {
        resolvedLedger = const WorkLedger();
      }
    }
    // 资料会话是权威来源；没有会话（旧作品 / 手工建的作品）才按台账宽松还原。
    var blueprint = session?.blueprint ?? ledgerToBlueprint(resolvedLedger);
    final summary = (work?.summary ?? '').trim();
    if (summary.isNotEmpty && summary != blueprint.storyCore.summary) {
      blueprint = blueprint.copyWith(
        storyCore: blueprint.storyCore.copyWith(
          summary: summary,
          logline: blueprint.storyCore.logline.isEmpty
              ? firstSentence(summary)
              : blueprint.storyCore.logline,
        ),
      );
    }
    return blueprint;
  }

  // ================================================================
  // 章节
  // ================================================================

  /// AI 起草本章（标题 / 概要 / 本章资料），流式返回全文，done 给出结构化草稿。
  ///
  /// 只生成与落库 AI 记录，不改动章节本身；调用方确认后再保存章节与本章资料。
  Future<ChapterDraftResult> draftChapter({
    required int workId,
    required int chapterNo,
    String? instruction,
    String? model,
    int? skillId,
    void Function(String delta)? onDelta,
  }) async {
    final body = await _api.postStream(
      ApiEndpoints.aiChapterDraftStream,
      data: <String, dynamic>{
        'workId': workId,
        'chapterNo': chapterNo,
        if (instruction != null && instruction.trim().isNotEmpty)
          'instruction': instruction.trim(),
        if (model != null && model.isNotEmpty) 'model': model,
        if (skillId != null) 'skillId': skillId,
      },
      receiveTimeout: _streamTimeout,
    );
    ChapterDraftResult? draft;
    final buffer = StringBuffer();
    await consumeSseEvents(body.stream, (event) {
      if (event.payload?['done'] == true) {
        final raw = event.payload?['draft'];
        draft = ChapterDraftResult.fromJson(
            raw is Map ? Map<String, dynamic>.from(raw) : null);
        return;
      }
      final delta = event.text('delta');
      if (delta.isNotEmpty) {
        buffer.write(delta);
        onDelta?.call(delta);
      }
    });
    if (draft == null) {
      throw ApiException(
        buffer.toString().trim().isEmpty
            ? '本次未返回章节草稿，请重试'
            : '生成中断，已保留收到的内容，请重试',
      );
    }
    if (!draft!.hasDraft) throw ApiException('本次未返回章节草稿，请重试');
    return draft!;
  }

  /// 本章资料整表。
  Future<ChapterMetaTable> chapterMeta(int workId) async {
    if (workId <= 0) return ChapterMetaTable.empty;
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkChapterMeta(workId),
      parser: _mapParser,
    );
    return ChapterMetaTable.fromJson(data);
  }

  /// 保存单章本章资料（整份覆盖）。
  Future<ChapterMeta> saveChapterMeta(
    int workId,
    int chapterNo,
    ChapterMeta meta,
  ) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.contentWorkChapterMetaByNo(workId, chapterNo),
      data: meta.toJson(),
      parser: _mapParser,
    );
    return data == null ? meta : ChapterMeta.fromJson(data);
  }

  /// 依据本章概要与正文整理本章资料（后端直接落库并返回结果）。
  Future<ChapterMeta> organizeChapterMeta({
    required int workId,
    required int chapterNo,
    String? instruction,
    String? model,
    int? skillId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.aiChapterMeta,
      data: <String, dynamic>{
        'workId': workId,
        'chapterNo': chapterNo,
        if (instruction != null && instruction.trim().isNotEmpty)
          'instruction': instruction.trim(),
        if (model != null && model.isNotEmpty) 'model': model,
        if (skillId != null) 'skillId': skillId,
      },
      receiveTimeout: _longTimeout,
      parser: _mapParser,
    );
    if (data == null) throw ApiException('整理本章资料失败，请稍后重试');
    return ChapterMeta.fromJson(data);
  }

  // ================================================================
  // 内部
  // ================================================================

  /// 消费作品资料 SSE：收集 stage / delta，done 事件解析会话。
  Future<BlueprintSession> _consumeBlueprintStream(
    Stream<Uint8List> stream, {
    void Function(String stage)? onStage,
    void Function(String delta)? onDelta,
  }) async {
    BlueprintSession? session;
    final buffer = StringBuffer();
    await consumeSseEvents(stream, (event) {
      if (event.payload?['done'] == true) {
        final raw = event.payload?['blueprint'];
        final sid = event.intValue('sessionId');
        session = BlueprintSession(
          sessionId: sid,
          status: 'draft',
          blueprint: StoryBlueprint.fromJson(
              raw is Map ? Map<String, dynamic>.from(raw) : null),
        );
        return;
      }
      final stage = event.text('stage');
      if (stage.isNotEmpty) onStage?.call(stage);
      final delta = event.text('delta');
      if (delta.isNotEmpty) {
        buffer.write(delta);
        onDelta?.call(delta);
      }
    });
    final result = session;
    if (result == null) {
      throw ApiException(
        buffer.toString().trim().isEmpty
            ? '本次未返回作品资料，请重试'
            : '生成中断，已保留收到的内容，请重试',
      );
    }
    if (result.sessionId <= 0) throw ApiException('生成响应缺少作品资料会话编号');
    return result;
  }

  /// 宽容解析 data；非对象结构（如作品无资料会话时的 null）由调用方判断。
  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
  }
}
