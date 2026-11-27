import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../ai/ai_quota_dialog.dart';
import '../../ai/data/ai_providers.dart';
import '../../bookstore/data/content_providers.dart';
import '../../welfare/data/welfare_providers.dart';
import '../data/ai_summary_hint_store.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';
import '../data/blueprint_providers.dart';
import '../data/chapter_ai_prompt.dart';
import '../data/chapter_meta_models.dart';
import '../widgets/blueprint_edit_sheets.dart';
import '../widgets/chapter_ai_sheet.dart';
import '../widgets/work_storyboard_tab.dart';
import 'chapter_page_widgets.dart';
import 'chapter_tabs.dart';

/// 全屏章节创作页（v3 工作台章节）：概要 / 正文 / 分镜 / 本章资料 四段切换。
///
/// 保留的既有能力：
///   - 输入停顿 3 秒自动保存（debounce），返回 / 点「完成」立即保存；
///   - 作品审核中只读保护；审核通过且已发布章节可单独设置试读；
///   - 返回前保存保护（新建章未填标题且有正文时先确认再放弃）。
///
/// v3 新增：
///   - 概要 Tab：首次进入（AI 起草过概要）显示「✦ AI 已按作品资料起草，可继续改」；
///     概要写回章节 `summary`（空串=清空，不传=不改）；
///   - 正文 / 分镜空态：✦ AI 创作 / 自己写；
///   - 分镜 Tab 真实对接作品分镜目录（`/content/works/{workId}/storyboards`）；
///   - 本章资料 Tab 对接 `chapter-meta`（出场人物 / 本章物品 / 本章关系）；
///   - 悬浮「AI 创作」胶囊 + 底部弹层：参考范围 chips + 写作要求，生成结果先预览、
///     用户确认后才写入（正文走 chapter-draft/stream，分镜走 storyboard/stream）。
class ChapterWritePage extends ConsumerStatefulWidget {
  const ChapterWritePage({
    super.key,
    required this.workId,
    this.chapterId = 0,
  });

  final int workId;

  /// 0 表示新建章节。
  final int chapterId;

  @override
  ConsumerState<ChapterWritePage> createState() => _ChapterWritePageState();
}

enum _ChapterTab { summary, text, storyboard, meta }

class _ChapterWritePageState extends ConsumerState<ChapterWritePage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _storyboardCtrl;

  int _chapterId = 0;
  int _chapterNo = 0;

  _ChapterTab _tab = _ChapterTab.summary;

  bool _dirty = false;
  bool _summaryDirty = false;
  bool _storyboardDirty = false;

  Timer? _autoSaveTimer;
  bool _saving = false;
  Future<bool>? _savingFuture;

  /// 正在提交正文 / 概要：期间的输入回调不置 dirty（见 [_onChanged]）。
  bool _savingSection = false;

  bool _initialized = false;
  bool _editable = false;
  bool _backing = false;
  bool _saveFailed = false;

  bool _isFree = false;
  bool _trialSaving = false;
  bool _openingStoryboard = false;

  /// 正文 Tab：作者是否已选择「自己写」（空正文时展示空态卡）。
  bool _textStarted = false;

  /// 分镜 Tab：作者是否已选择「自己写」。
  bool _storyboardStarted = false;

  /// 概要 Tab：AI 已起草概要的首次提示（只展示一次）。
  bool _showAiSummaryHint = false;
  bool _aiHintChecked = false;

  /// 悬浮 AI 弹层是否打开中（打开后隐藏胶囊，避免遮挡）。
  bool _aiSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _chapterId = widget.chapterId;
    _titleCtrl = TextEditingController();
    _summaryCtrl = TextEditingController();
    _contentCtrl = TextEditingController();
    _storyboardCtrl = TextEditingController();
    _titleCtrl.addListener(_onChanged);
    _summaryCtrl.addListener(_onSummaryChanged);
    _contentCtrl.addListener(_onChanged);
    _storyboardCtrl.addListener(_onStoryboardChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _contentCtrl.dispose();
    _storyboardCtrl.dispose();
    super.dispose();
  }

  // ================================================================
  // 初始化与派生
  // ================================================================

  AuthorWorkDetail? get _detail =>
      ref.read(authorWorkDetailProvider(widget.workId)).valueOrNull;

  AuthorChapterItem? get _chapter {
    for (final chapter in _detail?.chapters ?? const <AuthorChapterItem>[]) {
      if (chapter.chapterId == _chapterId) return chapter;
    }
    return null;
  }

  /// 本章资料：非 build 方法里读取，避免在异步流程中 watch。
  ChapterMeta get _meta =>
      ref.read(workChapterMetaProvider(widget.workId)).valueOrNull?.of(
            _chapter?.chapterNo ?? _chapterNo,
          ) ??
      ChapterMeta.empty;

  void _tryInitFromProvider() {
    if (_initialized) return;
    final detail = _detail;
    if (detail == null) return;
    _editable = detail.work.editable;
    if (_chapterId == 0) {
      // 新建章节：序号取当前最大 +1，标题默认「第 N 章」。
      _chapterNo = _nextChapterNo();
      _titleCtrl.removeListener(_onChanged);
      _titleCtrl.text = '第 $_chapterNo 章';
      _titleCtrl.addListener(_onChanged);
      _initialized = true;
      _loadStoryboardForNew();
      return;
    }
    final chapter = _chapter;
    if (chapter == null) return;
    _chapterNo = chapter.chapterNo;
    _titleCtrl.removeListener(_onChanged);
    _summaryCtrl.removeListener(_onSummaryChanged);
    _contentCtrl.removeListener(_onChanged);
    _titleCtrl.text = chapter.chapterTitle;
    _summaryCtrl.text = chapter.summary;
    _contentCtrl.text = chapter.content;
    _isFree = chapter.isFree;
    // 已有正文的章节直接进入正文编辑态，不再展示空态卡。
    _textStarted = chapter.content.trim().isNotEmpty;
    _titleCtrl.addListener(_onChanged);
    _summaryCtrl.addListener(_onSummaryChanged);
    _contentCtrl.addListener(_onChanged);
    // 分镜：从作品分镜目录回填本章分镜正文。
    _loadStoryboardInto(_chapterId);
    _initialized = true;
    _maybeShowAiSummaryHint();
  }

  void _loadStoryboardForNew() {
    // 新建章尚未落库，没有分镜可回填。
    _storyboardCtrl.text = '';
  }

  void _loadStoryboardInto(int chapterId) {
    final boards = ref.read(workStoryboardsProvider(widget.workId)).valueOrNull;
    final board = storyboardForChapter(boards, chapterId);
    if (board == null || _storyboardDirty) return;
    final content = (board['content'] ?? '').toString();
    _storyboardCtrl.removeListener(_onStoryboardChanged);
    _storyboardCtrl.text = content;
    _storyboardStarted = content.trim().isNotEmpty;
    _storyboardCtrl.addListener(_onStoryboardChanged);
    if (mounted) setState(() {});
  }

  /// 首次进入本章概要且为 AI 起草时展示提示（本地去重，编辑或再次进入不再打扰）。
  Future<void> _maybeShowAiSummaryHint() async {
    if (_aiHintChecked || _chapterNo <= 0) return;
    final table = ref.read(workChapterMetaProvider(widget.workId)).valueOrNull;
    // 本章资料尚未加载：等 provider 到达后由 build 里的 ref.listen 再判断。
    if (table == null) return;
    _aiHintChecked = true;
    if (!table.of(_chapterNo).isAiDrafted) return;
    final seen = await AiSummaryHintStore.hasSeen(widget.workId, _chapterNo);
    if (seen || !mounted) return;
    await AiSummaryHintStore.markSeen(widget.workId, _chapterNo);
    if (!mounted) return;
    setState(() => _showAiSummaryHint = true);
  }

  int _nextChapterNo() {
    var maxNo = 0;
    for (final chapter in _detail?.chapters ?? const <AuthorChapterItem>[]) {
      if (chapter.chapterNo > maxNo) maxNo = chapter.chapterNo;
    }
    return maxNo + 1;
  }

  String _previousChapterTail() {
    final chapters = _detail?.chapters ?? const <AuthorChapterItem>[];
    AuthorChapterItem? previous;
    for (final chapter in chapters) {
      if (chapter.chapterNo >= _chapterNo) continue;
      if (chapter.content.trim().isEmpty) continue;
      if (previous == null || chapter.chapterNo > previous.chapterNo) {
        previous = chapter;
      }
    }
    return previous?.content ?? '';
  }

  bool get _canSetTrial {
    if (!_editable || _dirty || _chapterId == 0) return false;
    final detail = _detail;
    bool approved = false;
    for (final chapter in detail?.chapters ?? const <AuthorChapterItem>[]) {
      if (chapter.chapterId == _chapterId && chapter.isApproved) approved = true;
    }
    return detail?.work.status == 'published' && approved;
  }

  // ================================================================
  // 输入与保存
  // ================================================================

  void _onChanged() {
    // 保存中的程序性回填（如详情刷新）不算用户修改。
    if (_savingSection) return;
    _dirty = true;
    _saveFailed = false;
    _scheduleAutoSave();
    setState(() {});
  }

  /// 3 秒防抖自动保存（保存期间被拦下的修改由 [_save] 结束后补调度）。
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), _autoSave);
  }

  void _onSummaryChanged() {
    _summaryDirty = true;
    _showAiSummaryHint = false;
    _onChanged();
  }

  void _onStoryboardChanged() {
    _storyboardDirty = true;
    _onChanged();
  }

  Future<void> _autoSave() async {
    if (_saving || !_dirty) return;
    await _save(silent: true);
  }

  Future<bool> _save({bool silent = false}) async {
    if (!_editable) return true;
    if (_savingFuture != null) return _savingFuture!;
    final title = _titleCtrl.text.trim();
    if (_chapterId == 0 && title.isEmpty) {
      if (!silent) _toast('请先填写章节标题');
      return false;
    }
    final completer = Completer<bool>();
    _savingFuture = completer.future;
    if (mounted) setState(() => _saving = true);
    var ok = false;
    // 保存正文 / 概要期间的请求飞行窗口：此时输入框回调不应把已提交的字段再标记为 dirty。
    _savingSection = true;
    try {
      final repo = ref.read(authorWorkRepositoryProvider);
      final summary = _summaryCtrl.text;
      final contentSnapshot = _contentCtrl.text;
      final titleSnapshot = _titleCtrl.text.trim();
      final storyboardSnapshot = _storyboardCtrl.text;
      final hadSummaryDirty = _summaryDirty;
      if (_chapterId == 0) {
        final newId = await repo.addChapter(
          widget.workId,
          chapterNo: _chapterNo,
          chapterTitle: title,
          content: _contentCtrl.text,
          summary: summary,
        );
        _chapterId = newId;
      } else {
        await repo.updateChapter(
          _chapterId,
          workId: widget.workId,
          chapterTitle: title,
          content: _contentCtrl.text,
          // 概要：只有作者改过才下发（空串=清空、不传=不改）。
          summary: hadSummaryDirty ? summary : null,
        );
      }
      // 分镜有改动才写分镜目录（独立接口，失败不拖累章节保存）。
      if (_storyboardDirty && _chapterId > 0) {
        try {
          await ref.read(aiRepositoryProvider).saveStoryboard(
                workId: widget.workId,
                title: title.isEmpty ? '第 $_chapterNo 章' : title,
                content: _storyboardCtrl.text,
                source: 'manual',
                chapterId: _chapterId,
              );
          ref.invalidate(workStoryboardsProvider(widget.workId));
          _storyboardDirty = false;
        } on ApiException catch (e) {
          if (!silent) _toast('分镜保存失败：${e.message}');
          ok = true;
        }
      }
      // 保存期间用户若继续输入，保持 dirty 交给下一轮自动保存。
      _dirty = _titleCtrl.text.trim() != titleSnapshot ||
          _contentCtrl.text != contentSnapshot ||
          _summaryCtrl.text != summary ||
          _storyboardCtrl.text != storyboardSnapshot;
      // 保存期间用户继续改概要：保留 dirty，下一轮保存必须继续带 summary。
      _summaryDirty = _summaryCtrl.text != summary;
      if (_storyboardCtrl.text != storyboardSnapshot) _storyboardDirty = true;
      _saveFailed = false;
      ref.invalidate(authorWorkDetailProvider(widget.workId));
      if (!silent) _toast('已保存');
      ok = true;
    } on ApiException catch (e) {
      if (!silent) {
        if (mounted) _toast(e.message);
      } else {
        _saveFailed = true;
      }
    } catch (_) {
      if (!silent) {
        if (mounted) _toast('保存失败，请稍后重试');
      } else {
        _saveFailed = true;
      }
    } finally {
      _savingSection = false;
      completer.complete(ok);
      _savingFuture = null;
      if (mounted) {
        setState(() => _saving = false);
        // 飞行过程中的新修改被 _onChanged 拦下了，这里补一次自动保存调度。
        if (_dirty) _scheduleAutoSave();
      }
    }
    return ok;
  }

  Future<void> _setTrial(bool value) async {
    if (!_canSetTrial || _trialSaving || _saving) return;
    setState(() => _trialSaving = true);
    try {
      await ref.read(authorWorkRepositoryProvider).updateChapter(
            _chapterId,
            workId: widget.workId,
            isFree: value,
          );
      if (!mounted) return;
      setState(() => _isFree = value);
      ref.invalidate(authorWorkDetailProvider(widget.workId));
      _toast(value ? '已开启章节试读' : '已关闭章节试读');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('试读设置未保存，请稍后重试');
    } finally {
      if (mounted) setState(() => _trialSaving = false);
    }
  }

  Future<void> _onBack() async {
    if (_backing) return;
    _backing = true;
    _autoSaveTimer?.cancel();
    try {
      final hasContent = _contentCtrl.text.trim().isNotEmpty;
      final title = _titleCtrl.text.trim();
      if (_chapterId == 0 && hasContent && title.isEmpty && _editable) {
        final discard = await _confirmDiscard();
        if (!discard) return;
      } else if (_dirty && _editable) {
        await _save(silent: true);
      }
      if (mounted) context.pop();
    } finally {
      _backing = false;
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('内容未保存'),
        content: const Text('当前章节未填写标题，正文将无法保存，确定放弃吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续编辑')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('放弃')),
        ],
      ),
    );
    return ok ?? false;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ================================================================
  // 本章资料
  // ================================================================

  Future<void> _organizeMeta() async {
    if (!_editable || _chapterId == 0) {
      _toast('请先保存章节后再整理本章资料');
      return;
    }
    if (_dirty && !await _save(silent: true)) return;
    if (!mounted) return;
    final quota = ref.read(welfareAssetProvider).valueOrNull;
    if (quota != null && quota.points.balance == 0) {
      await showAiQuotaInsufficientDialog(context);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(blueprintRepositoryProvider).organizeChapterMeta(
            workId: widget.workId,
            chapterNo: _chapterNo,
          );
      ref.invalidate(workChapterMetaProvider(widget.workId));
      ref.invalidate(welfareAssetProvider);
      if (mounted) _toast('本章资料已整理并保存');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      } else {
        _toast(e.message);
      }
    } catch (_) {
      if (mounted) _toast('整理本章资料失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editChapterMeta() async {
    final meta = _meta;
    final castText = meta.cast
        .map((entry) => '${entry.name}：${entry.change.isEmpty ? entry.role : entry.change}')
        .join('\n');
    final itemsText = meta.items
        .map((entry) => '${entry.name}：${entry.change.isEmpty ? entry.role : entry.change}')
        .join('\n');
    final edgesText = meta.edges.map((edge) {
      final a = _blueprintCharacterName(edge.a);
      final b = _blueprintCharacterName(edge.b);
      return '$a ↔ $b：${edge.label}${edge.dash ? '（虚线）' : ''}';
    }).join('\n');
    final result = await showBlueprintFieldsSheet(
      context,
      title: '编辑本章资料',
      subtitle: '一行一条；人物与物品须来自作品资料，关系写成「A ↔ B：关系」',
      enabled: _editable,
      fields: [
        BlueprintField(
          label: '本章出场人物',
          value: castText,
          multiline: true,
          hintText: '一行一位：姓名：本章变化',
        ),
        BlueprintField(
          label: '本章物品',
          value: itemsText,
          multiline: true,
          hintText: '一行一件：名称：本章用途或变化',
        ),
        BlueprintField(
          label: '本章关系',
          value: edgesText,
          multiline: true,
          hintText: '一行一条：姓名A ↔ 姓名B：关系（加上「虚线」表示隐瞒/质疑）',
        ),
      ],
    );
    if (result == null || !mounted) return;
    final blueprint = ref.read(workBlueprintProvider(widget.workId)).valueOrNull;
    if (blueprint == null) {
      _toast('作品资料尚未加载，请稍后重试');
      return;
    }
    String keyOf(String name) => blueprint.characterByName(name)?.key ?? '';
    String itemKeyOf(String name) {
      for (final item in blueprint.items) {
        if (item.name == name) return item.key;
      }
      return '';
    }

    List<ChapterMetaEntry> parseEntries(String raw, String Function(String) key) {
      final entries = <ChapterMetaEntry>[];
      for (final line in raw.split('\n')) {
        final text = line.trim();
        if (text.isEmpty) continue;
        final index = text.indexOf(RegExp(r'[：:]'));
        final name = index <= 0 ? text : text.substring(0, index).trim();
        final value = index <= 0 ? '' : text.substring(index + 1).trim();
        final resolved = key(name);
        if (resolved.isEmpty) continue;
        entries.add(ChapterMetaEntry(key: resolved, name: name, change: value));
      }
      return entries;
    }

    final cast = parseEntries(result['本章出场人物'] ?? '', keyOf);
    final items = parseEntries(result['本章物品'] ?? '', itemKeyOf);
    final edges = <ChapterMetaEdge>[];
    for (final line in (result['本章关系'] ?? '').split('\n')) {
      final text = line.trim();
      if (text.isEmpty) continue;
      final match = RegExp(r'^(.{1,24}?)\s*(?:↔|<->|⇄|—|－|-|与|和)\s*(.{1,24}?)\s*[：:]\s*(.+)$')
          .firstMatch(text);
      if (match == null) continue;
      final a = keyOf(match.group(1)!.trim());
      final b = keyOf(match.group(2)!.trim());
      if (a.isEmpty || b.isEmpty || a == b) continue;
      final rawLabel = match.group(3)!.trim();
      final dash = rawLabel.contains('虚线') ||
          RegExp(r'隐瞒|质疑|怀疑|未公开|推断').hasMatch(rawLabel);
      edges.add(ChapterMetaEdge(
        a: a,
        b: b,
        label: rawLabel.replaceAll('（虚线）', '').replaceAll('(虚线)', '').trim(),
        dash: dash,
      ));
    }
    setState(() => _saving = true);
    try {
      await ref.read(blueprintRepositoryProvider).saveChapterMeta(
            widget.workId,
            _chapterNo,
            ChapterMeta(
              cast: cast,
              items: items,
              edges: edges,
              aiSummary: meta.aiSummary,
              source: 'manual',
            ),
          );
      ref.invalidate(workChapterMetaProvider(widget.workId));
      if (mounted) _toast('本章资料已保存');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _blueprintCharacterName(String key) {
    final blueprint = ref.read(workBlueprintProvider(widget.workId)).valueOrNull;
    return blueprint?.characterByKey(key)?.name ?? '';
  }

  // ================================================================
  // AI 创作
  // ================================================================

  /// 底部 AI 创作弹层：先预览、确认后写入。
  Future<void> _openAiSheet({required AiDraftMode mode}) async {
    if (!_editable || _aiSheetOpen) return;
    if (_dirty) await _save(silent: true);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _aiSheetOpen = true);
    try {
      final result = await showChapterAiSheet(
        context,
        mode: mode,
        workTitle: _detail?.work.title ?? '',
        chapterNo: _chapterNo,
        chapterTitle: _titleCtrl.text.trim(),
        chapterSummary: _summaryCtrl.text.trim(),
        currentContent: _contentCtrl.text,
        canEdit: _editable,
        generate: ({
          required String instruction,
          required bool refsWork,
          required bool refsSummary,
          required bool refsPrev,
          required void Function(String delta) onDelta,
        }) async {
          if (mode == AiDraftMode.text) {
            return _generateText(
              instruction: instruction,
              refsWork: refsWork,
              refsSummary: refsSummary,
              refsPrev: refsPrev,
              onDelta: onDelta,
            );
          }
          return _generateStoryboard(
            instruction: instruction,
            refsWork: refsWork,
            refsSummary: refsSummary,
            refsPrev: refsPrev,
            onDelta: onDelta,
          );
        },
      );
      if (result == null || !mounted) return;
      if (result.mode == AiDraftMode.text) {
        _applyTextDraft(result.content);
      } else {
        await _applyStoryboardDraft(result.content);
      }
    } finally {
      if (mounted) setState(() => _aiSheetOpen = false);
    }
  }

  /// 正文草稿：`write/stream` 流式输出纯正文（按所选参考范围注入上下文）。
  Future<String> _generateText({
    required String instruction,
    required bool refsWork,
    required bool refsSummary,
    required bool refsPrev,
    required void Function(String delta) onDelta,
  }) async {
    final castNames = _meta.cast.map((entry) => entry.name).toList();
    final ledger = ref.read(workLedgerProvider(widget.workId)).valueOrNull;
    final prompt = buildChapterWritePrompt(
      workTitle: _detail?.work.title ?? '',
      chapterNo: _chapterNo,
      chapterTitle: _titleCtrl.text.trim(),
      chapterSummary: _summaryCtrl.text,
      ledgerBlock: ledgerPromptBlock(ledger, castNames: castNames),
      previousTail: _previousChapterTail(),
      refsWork: refsWork,
      refsSummary: refsSummary,
      refsPrev: refsPrev,
      instruction: instruction,
    );
    final buffer = StringBuffer();
    await ref.read(aiRepositoryProvider).writeStream(
          prompt: prompt,
          type: 'script',
          workId: widget.workId,
          onDelta: (delta) {
            buffer.write(delta);
            onDelta(delta);
          },
        );
    return buffer.toString();
  }

  Future<String> _generateStoryboard({
    required String instruction,
    required bool refsWork,
    required bool refsSummary,
    required bool refsPrev,
    required void Function(String delta) onDelta,
  }) async {
    final castNames = _meta.cast.map((entry) => entry.name).toList();
    final ledger = ref.read(workLedgerProvider(widget.workId)).valueOrNull;
    final script = buildChapterStoryboardScript(
      workTitle: _detail?.work.title ?? '',
      chapterNo: _chapterNo,
      chapterTitle: _titleCtrl.text.trim(),
      chapterSummary: _summaryCtrl.text,
      ledgerBlock: ledgerPromptBlock(ledger, castNames: castNames),
      previousTail: _previousChapterTail(),
      currentContent: _contentCtrl.text,
      refsWork: refsWork,
      refsSummary: refsSummary,
      refsPrev: refsPrev,
      instruction: instruction,
    );
    final buffer = StringBuffer();
    await ref.read(aiRepositoryProvider).storyboardStream(
          script: script,
          workId: widget.workId,
          chapterTitle: _titleCtrl.text.trim(),
          onDelta: (delta) {
            buffer.write(delta);
            onDelta(delta);
          },
        );
    return buffer.toString();
  }

  void _applyTextDraft(String draft) {
    final text = draft.trim();
    if (text.isEmpty) return;
    final existing = _contentCtrl.text;
    final updated = existing.trim().isEmpty
        ? text
        : appendChapterText(existing, text);
    _contentCtrl.text = updated;
    _contentCtrl.selection = TextSelection.collapsed(offset: updated.length);
    _textStarted = true;
    _tab = _ChapterTab.text;
    _onChanged();
    _toast(existing.trim().isEmpty ? '已插入正文，可以继续改' : '已追加到正文末尾，可以继续改');
  }

  Future<void> _applyStoryboardDraft(String draft) async {
    final result = appendStoryboardShots(_storyboardCtrl.text, draft);
    if (result.added == 0) {
      _toast('本次没有可插入的分镜行');
      return;
    }
    _storyboardCtrl.text = result.content;
    _storyboardCtrl.selection =
        TextSelection.collapsed(offset: result.content.length);
    _storyboardStarted = true;
    _tab = _ChapterTab.storyboard;
    _onStoryboardChanged();
    _toast('已应用 ${result.added} 个分镜，可继续修改');
  }

  /// 概要 Tab「按这版概要写正文 →」：切到正文并打开 AI 弹层（正文模式）。
  Future<void> _writeFromSummary() async {
    if (!_editable) return;
    setState(() => _tab = _ChapterTab.text);
    await _openAiSheet(mode: AiDraftMode.text);
  }

  Future<void> _openStandaloneStoryboard() async {
    if (!_editable || _openingStoryboard) return;
    if (_dirty && !await _save(silent: true)) return;
    if (!mounted) return;
    if (_chapterId <= 0) {
      _toast('请先保存章节后再创作分镜');
      return;
    }
    setState(() => _openingStoryboard = true);
    try {
      await context.push(RoutePath.aiStoryboardUrl(
        workId: widget.workId,
        chapterId: _chapterId,
      ));
      ref.invalidate(workStoryboardsProvider(widget.workId));
      _loadStoryboardInto(_chapterId);
    } finally {
      if (mounted) setState(() => _openingStoryboard = false);
    }
  }

  // ================================================================
  // 构建
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(authorWorkDetailProvider(widget.workId));
    final detail = detailAsync.valueOrNull;
    if (detail != null) {
      _editable = detail.work.editable;
      if (!_initialized) _tryInitFromProvider();
    }
    ref.listen(workChapterMetaProvider(widget.workId), (_, __) {
      _maybeShowAiSummaryHint();
    });
    // 分镜目录是异步读取的：首次打开时数据可能尚未到达，到达后再回填本章分镜。
    ref.listen(workStoryboardsProvider(widget.workId), (_, next) {
      if (_chapterId <= 0 || next.valueOrNull == null) return;
      _loadStoryboardInto(_chapterId);
    });
    final isNew = _chapterId == 0;
    final appTitle = isNew
        ? '新建章节'
        : '第 $_chapterNo 章';
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBack,
          ),
          title: Text(appTitle),
          actions: [
            if (!isNew)
              TextButton(
                // 与左上角返回、系统返回同一套「先保存再离开」防丢逻辑。
                onPressed: _onBack,
                child: const Text('目录'),
              ),
            if (_editable)
              TextButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final router = GoRouter.of(context);
                        final ok = await _save();
                        if (!mounted) return;
                        if (ok) router.pop();
                      },
                child: const Text('完成'),
              ),
          ],
        ),
        body: detail == null
            ? const LoadingView(message: '加载中')
            : Column(
                children: [
                  _buildHeader(),
                  if (_canSetTrial)
                    ChapterTrialRow(
                      value: _isFree,
                      busy: _trialSaving || _saving,
                      onChanged: _setTrial,
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            ChapterTabBar<_ChapterTab>(
                              current: _tab,
                              tabs: const [
                                (_ChapterTab.summary, '概要'),
                                (_ChapterTab.text, '正文'),
                                (_ChapterTab.storyboard, '分镜'),
                                (_ChapterTab.meta, '本章资料'),
                              ],
                              onChanged: (tab) {
                                if (_dirty) {
                                  _save(silent: true);
                                }
                                setState(() => _tab = tab);
                              },
                            ),
                            Expanded(child: _buildTabBody()),
                          ],
                        ),
                        if (_showFloatingAi)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: ChapterAiPill(
                              onTap: () => _openAiSheet(
                                mode: _tab == _ChapterTab.storyboard
                                    ? AiDraftMode.storyboard
                                    : AiDraftMode.text,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ChapterStatusBar(
                    tabLabel: switch (_tab) {
                      _ChapterTab.summary => '概要',
                      _ChapterTab.text => '正文',
                      _ChapterTab.storyboard => '分镜',
                      _ChapterTab.meta => '本章资料',
                    },
                    detail: switch (_tab) {
                      _ChapterTab.summary =>
                        '${_summaryCtrl.text.replaceAll(RegExp(r'\s'), '').length} 字',
                      _ChapterTab.text =>
                        '${_contentCtrl.text.replaceAll(RegExp(r'\s'), '').length} 字',
                      _ChapterTab.storyboard =>
                        '${_storyboardCtrl.text.split('\n').where((line) => line.trim().isNotEmpty).length} 行',
                      _ChapterTab.meta =>
                        '${_meta.cast.length} 人 · ${_meta.items.length} 件',
                    },
                    saving: _saving,
                    dirty: _dirty,
                    failed: _saveFailed,
                    editable: _editable,
                    isFree: _canSetTrial && _isFree,
                    onRetry: _autoSave,
                  ),
                ],
              ),
      ),
    );
  }

  bool get _showFloatingAi =>
      _editable &&
      !_aiSheetOpen &&
      (_tab == _ChapterTab.summary ||
          _tab == _ChapterTab.text ||
          _tab == _ChapterTab.storyboard);

  Widget _buildHeader() {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: _titleCtrl,
        enabled: _editable,
        maxLines: 1,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          hintText: '章节标题',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.text1,
        ),
      ),
    );
  }

  Widget _buildTabBody() {
    switch (_tab) {
      case _ChapterTab.summary:
        return ChapterSummaryTab(
          controller: _summaryCtrl,
          editable: _editable,
          showAiDraftedHint: _showAiSummaryHint,
          onWriteFromSummary: _writeFromSummary,
        );
      case _ChapterTab.text:
        return ChapterTextTab(
          controller: _contentCtrl,
          editable: _editable,
          started: _textStarted,
          onStartWriting: () => setState(() => _textStarted = true),
          onAiCreate: () => _openAiSheet(mode: AiDraftMode.text),
        );
      case _ChapterTab.storyboard:
        final board = storyboardForChapter(
          ref.watch(workStoryboardsProvider(widget.workId)).valueOrNull,
          _chapterId,
        );
        return ChapterStoryboardTab(
          workId: widget.workId,
          controller: _storyboardCtrl,
          editable: _editable,
          started: _storyboardStarted,
          board: board,
          openingStandalone: _openingStoryboard,
          onStartWriting: () => setState(() => _storyboardStarted = true),
          onAiCreate: () => _openAiSheet(mode: AiDraftMode.storyboard),
          onOpenStandalone: _openStandaloneStoryboard,
        );
      case _ChapterTab.meta:
        final table =
            ref.watch(workChapterMetaProvider(widget.workId)).valueOrNull;
        final blueprint =
            ref.watch(workBlueprintProvider(widget.workId)).valueOrNull;
        if (blueprint == null) {
          return const Center(child: Text('作品资料加载中…'));
        }
        final resolvedTable = table ?? ChapterMetaTable.empty;
        return ChapterMetaTab(
          workId: widget.workId,
          chapterNo: _chapterNo,
          meta: resolvedTable.of(_chapter?.chapterNo ?? _chapterNo),
          blueprint: blueprint,
          metaTable: resolvedTable,
          chapterTitles: {
            for (final chapter in _detail?.chapters ?? const <AuthorChapterItem>[])
              chapter.chapterNo: chapter.chapterTitle,
          },
          editable: _editable,
          busy: _saving,
          onOrganize: _organizeMeta,
          onEditMeta: _editChapterMeta,
        );
    }
  }

}
