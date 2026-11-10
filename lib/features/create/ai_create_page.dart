import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../ai/ai_quota_dialog.dart';
import '../ai/data/ai_providers.dart';
import '../ai/widgets/ai_model_selector.dart';
import '../ai/widgets/ai_skill_selector.dart';
import '../welfare/data/welfare_providers.dart';
import 'data/ai_create_session.dart';
import 'data/author_work_providers.dart';
import 'data/create_providers.dart';

/// AI 创作页（创作者端）：设定 → 大纲 → 章节三步，与 PC 创作者端流程一致。
///
/// - 设定：书名、灵感、题材、集数、导演(skill)、模型；展示剩余积分。
/// - 大纲：流式生成并实时列出已出现的分集，可手动编辑后再确认。
/// - 章节：确认大纲时创建草稿作品，逐章生成并逐章落库，完成后进入作品工作台。
///
/// 章节 prompt 带 [kAiCreateMark] 前缀，供「AI 记录」按会话合并成一条。
class AiCreatePage extends ConsumerStatefulWidget {
  const AiCreatePage({super.key, this.draft});

  final AiCreateDraft? draft;

  @override
  ConsumerState<AiCreatePage> createState() => _AiCreatePageState();
}

class _ChapterTask {
  _ChapterTask({required this.title, required this.summary});

  final String title;
  final String summary;
  bool selected = true;
  String state = 'idle'; // idle / generating / generated / failed
  String content = '';
  String streaming = '';
  int chapterId = 0;
  bool remote = false;
  bool recovered = false;
  String error = '';

  int get streamingChars => streaming.length;
}

class _AiCreatePageState extends ConsumerState<AiCreatePage> {
  int _step = 1;

  final _titleCtrl = TextEditingController();
  final _ideaCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  final _episodesCtrl = TextEditingController(text: '12');
  int? _skillId;
  String? _model;

  String _outline = '';
  bool _outlineBusy = false;
  bool _outlineEditing = false;
  // 大纲局部改写：选中段落 + 作者意见，流式期间原位替换。
  ({int start, int end, String passage})? _reviseSelection;
  String _reviseInstruction = '';
  final _reviseCtrl = TextEditingController();
  bool _revising = false;

  int _workId = 0;
  // 本次新建作品已写入的章节数：章节序号从这里顺延，避免详情缓存未刷新时重号。
  int _writtenChapters = 0;
  bool _creating = false;
  String _createError = '';
  final List<_ChapterTask> _chapters = [];
  bool _running = false;
  bool _stopping = false;
  int _runningIndex = -1;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft == null) return;
    // 从 AI 记录恢复：带回设定、大纲与已生成章节，直接进入章节步骤。
    _titleCtrl.text = draft.title;
    _ideaCtrl.text = draft.idea;
    _genreCtrl.text = draft.genre;
    _episodesCtrl.text = '${draft.episodes}';
    _outline = draft.outline;
    _step = 3;
    _chapters.addAll(draft.chapters.map((c) => _ChapterTask(title: c.title, summary: '')
      ..state = 'generated'
      ..content = c.content
      ..recovered = true));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _ideaCtrl.dispose();
    _genreCtrl.dispose();
    _episodesCtrl.dispose();
    _reviseCtrl.dispose();
    super.dispose();
  }

  int get _episodes => int.tryParse(_episodesCtrl.text.trim()) ?? 0;

  List<AiCreateChapterSeed> get _parsed => parseOutlineChapters(_outline);

  List<String> get _streamingTitles => listOutlineEpisodeTitles(_outline);

  int get _generatedCount => _chapters.where((c) => c.state == 'generated').length;

  int get _selectedCount => _chapters.where((c) => c.selected).length;

  double get _progress => _chapters.isEmpty ? 0 : _generatedCount / _chapters.length;

  int get _quota => ref.watch(welfareAssetProvider).valueOrNull?.points.balance ?? 0;

  Future<void> _generateOutline() async {
    if (_titleCtrl.text.trim().isEmpty) {
      showAppToast(context, '请输入书名');
      return;
    }
    if (_ideaCtrl.text.trim().isEmpty) {
      showAppToast(context, '请先输入故事灵感或主题');
      return;
    }
    if (_episodes < 1 || _episodes > 200) {
      showAppToast(context, '集数需为 1–200 的整数');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _step = 2;
      _outlineBusy = true;
      _outline = '';
    });
    final inspiration = '书名：${_titleCtrl.text.trim()}\n'
        '故事灵感：${_ideaCtrl.text.trim()}\n'
        '请提供 $_episodes 个分集，每集单独一行标题，格式为“第1集：章节名称”，下一行写该集剧情概要。';
    try {
      final result = await ref.read(aiRepositoryProvider).outlineStream(
            inspiration: inspiration,
            genre: _genreCtrl.text.trim(),
            style: '共 $_episodes 集',
            skillId: _skillId,
            model: _model,
            onDelta: (delta) {
              if (mounted) setState(() => _outline += delta);
            },
          );
      if (!mounted) return;
      setState(() => _outline = result.outlineText);
      ref.invalidate(welfareAssetProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      } else {
        showAppToast(context, e.message);
      }
    } catch (_) {
      if (mounted) showAppToast(context, '大纲生成失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _outlineBusy = false);
    }
  }

  Future<void> _goChapters() async {
    if (_outlineBusy) return;
    final parsed = _parsed;
    if (parsed.isEmpty) {
      showAppToast(context, '未识别到分集标题，请按「第1集：章节名称」每行一个标题修改');
      return;
    }
    setState(() {
      _step = 3;
      _chapters
        ..clear()
        ..addAll(parsed.map((s) => _ChapterTask(title: s.title, summary: s.summary)));
    });
    await _ensureWork();
  }

  Future<int> _ensureWork() async {
    if (_workId > 0) return _workId;
    if (_creating) return 0;
    setState(() {
      _creating = true;
      _createError = '';
    });
    try {
      final description = outlineSummaryText(_outline);
      final id = await ref.read(createRepositoryProvider).createWork(
            title: _titleCtrl.text.trim(),
            description:
                description.isEmpty ? '由 AI 创作的《${_titleCtrl.text.trim()}》。' : description,
          );
      if (!mounted) return 0;
      setState(() => _workId = id);
      ref.invalidate(myWorksProvider);
      ref.invalidate(authorWorkDetailProvider(id));
      return id;
    } on ApiException catch (e) {
      if (!mounted) return 0;
      setState(() => _createError = e.message);
      return 0;
    } catch (_) {
      if (!mounted) return 0;
      setState(() => _createError = '作品创建失败，请重试');
      return 0;
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _writePrompt(_ChapterTask task) => '请根据以下完整大纲，为“${task.title}”创作正文，只写这一章。\n'
      '完整大纲：\n$_outline\n'
      '本章剧情概要：\n${task.summary}';

  String _continuePrompt(_ChapterTask task, String generated) {
    final tail = generated.length > 8000 ? generated.substring(generated.length - 8000) : generated;
    return '请根据大纲和本章概要，从已有正文的末尾接着写完“${task.title}”。不要重复已有正文，不要写其他章节。\n'
        '完整大纲：\n$_outline\n'
        '本章概要：\n${task.summary}\n'
        '已有正文末尾：\n$tail';
  }

  Future<void> _runChapter(_ChapterTask task) async {
    setState(() {
      task
        ..state = 'generating'
        ..streaming = ''
        ..error = '';
      _runningIndex = _chapters.indexOf(task);
    });
    try {
      final repo = ref.read(aiRepositoryProvider);
      var output = await repo.writeStream(
        prompt: markAiCreatePrompt(_writePrompt(task)),
        type: 'script',
        skillId: _skillId,
        model: _model,
        workId: _workId > 0 ? _workId : null,
        onDelta: (delta) {
          if (mounted) setState(() => task.streaming += delta);
        },
      );
      var generated = output.content;
      _truncatedThisChapter = output.content.length >= 4000;
      // 续写只在模型达到长度上限（生成被截断）时询问；其余情况直接成章。
      while (!_stopping && _truncatedThisChapter && await _confirmContinue(task.title)) {
        output = await repo.writeStream(
          prompt: markAiCreatePrompt(_continuePrompt(task, generated)),
          type: 'script',
          skillId: _skillId,
          model: _model,
          workId: _workId > 0 ? _workId : null,
          onDelta: (delta) {
            if (mounted) setState(() => task.streaming += delta);
          },
        );
        generated += output.content;
        _truncatedThisChapter = output.content.isNotEmpty && output.content.length >= 4000;
      }
      if (!mounted) return;
      final works = ref.read(authorWorkRepositoryProvider);
      if (task.remote && task.chapterId > 0) {
        await works.updateChapter(task.chapterId, content: generated);
      } else {
        final chapterId = await works.addChapter(
          _workId,
          chapterNo: _nextChapterNo(),
          chapterTitle: task.title,
          content: generated,
        );
        if (mounted) setState(() => task.chapterId = chapterId);
        _writtenChapters += 1;
      }
      setState(() {
        task
          ..content = generated
          ..streaming = ''
          ..state = 'generated'
          ..remote = true;
      });
      ref.invalidate(authorWorkDetailProvider(_workId));
      ref.invalidate(welfareAssetProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      } else if (mounted) {
        showAppToast(context, e.message);
      }
      if (!mounted) return;
      setState(() {
        task
          ..state = 'failed'
          ..error = e.message;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          task
            ..state = 'failed'
            ..error = '生成失败，请重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          task.streaming = '';
          _runningIndex = -1;
        });
      }
    }
  }

  /// 新建作品内下一个章节序号（新建作品从 1 开始，按本地写入计数顺延）。
  int _nextChapterNo() => _writtenChapters + 1;

  /// 流结束后询问是否续写（与 PC 创作工作台一致）。不需要续写时返回 false。
  Future<bool> _confirmContinue(String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('章节需要续写'),
        content: Text('「$title」达到单次生成长度上限。续写会额外消耗积分，是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('暂时停止')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('续写本章')),
        ],
      ),
    );
    return ok ?? false;
  }

  bool _truncatedThisChapter = false;

  Future<void> _startGeneration() async {
    if (_running || _selectedCount == 0) return;
    if (_workId == 0 && await _ensureWork() == 0) return;
    setState(() {
      _running = true;
      _stopping = false;
    });
    try {
      for (final task in _chapters) {
        if (_stopping) break;
        if (!task.selected || task.state == 'generated') continue;
        await _runChapter(task);
      }
      if (mounted && _generatedCount > 0) {
        showAppToast(context, '已生成 $_generatedCount 章并保存到作品');
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _stopping = false;
        });
      }
    }
  }

  Future<void> _finishToWork() async {
    if (_running || _saving) return;
    if (_workId == 0 && await _ensureWork() == 0) return;
    setState(() => _saving = true);
    try {
      if (!mounted) return;
      final router = GoRouter.of(context);
      await router.push(RoutePath.workWorkspaceUrl(workId: _workId, title: _titleCtrl.text.trim()));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('正在生成章节'),
        content: const Text('离开会停止生成；已生成的章节会保存在作品中。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('继续等待')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('离开')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        final leave = await _confirmLeave();
        if (!leave) return;
        if (mounted) router.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('AI 创作'),
          backgroundColor: Colors.white,
          elevation: 0.5,
          actions: [
            if (_step > 1 && !_running)
              TextButton(onPressed: () => setState(() => _step = 1), child: const Text('回到设定')),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: _StepBar(step: _step),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_step == 1) _buildSetup(),
            if (_step == 2) _buildOutline(),
            if (_step == 3) _buildChapters(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSetup() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('作品设定', subtitle: '先写清楚要讲的故事，AI 会据此生成剧本大纲。'),
          _Labeled(
            '书名 *',
            TextField(
              controller: _titleCtrl,
              maxLength: 100,
              decoration: const InputDecoration(hintText: '例如：深夜频率', counterText: ''),
            ),
          ),
          _Labeled(
            '故事灵感 *',
            TextField(
              controller: _ideaCtrl,
              maxLines: 4,
              minLines: 3,
              decoration: const InputDecoration(hintText: '例如：一位深夜电台主播在听众留言里听到了十年前的自己'),
            ),
          ),
          _Labeled(
            '题材',
            TextField(controller: _genreCtrl, decoration: const InputDecoration(hintText: '例如：都市情感、悬疑')),
          ),
          _Labeled(
            '集数',
            TextField(
              controller: _episodesCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: '1–200'),
            ),
          ),
          AiSkillSelector(
            selectedSkillId: _skillId,
            onChanged: (v) => setState(() => _skillId = v),
            skillTypeFilter: 'write',
          ),
          const SizedBox(height: 12),
          AiModelSelector(selectedModel: _model, onChanged: (v) => setState(() => _model = v)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text('剩余 $_quota 积分', style: const TextStyle(fontSize: 12, color: AppColors.text3))),
              FilledButton(onPressed: _generateOutline, child: const Text('下一步：生成大纲')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutline() {
    final titles = _streamingTitles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle(
                '剧本大纲',
                subtitle: _outlineBusy
                    ? '正在生成${titles.isEmpty ? '' : ' · 已写出 ${titles.length} 集'}'
                    : '可直接修改，确认后再逐章生成正文',
                trailing: _outline.isNotEmpty && !_outlineBusy
                    ? TextButton(
                        onPressed: () => setState(() => _outlineEditing = !_outlineEditing),
                        child: Text(_outlineEditing ? '完成编辑' : '手动编辑'),
                      )
                    : null,
              ),
              if (_outlineBusy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (titles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final title in titles)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(12)),
                          child: Text(title, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                        ),
                    ],
                  ),
                ),
              if (_outlineEditing)
                TextField(
                  controller: TextEditingController(text: _outline),
                  onChanged: (v) => _outline = v,
                  maxLines: null,
                  minLines: 14,
                  decoration: const InputDecoration(hintText: 'AI 生成的大纲会出现在这里'),
                )
              else
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 120),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(AppRadius.rSmall)),
                  child: SelectableText(
                    _outline.isEmpty ? '正在生成大纲…' : _outline,
                    style: const TextStyle(fontSize: 14, height: 1.8, color: AppColors.text2),
                    contextMenuBuilder: (context, state) {
                      final buttons = state.contextMenuButtonItems;
                      if (state.textEditingValue.selection.isValid &&
                          !state.textEditingValue.selection.isCollapsed) {
                        buttons.insert(
                          0,
                          ContextMenuButtonItem(
                            label: '修改这段',
                            onPressed: () {
                              state.hideToolbar();
                              _pickPassageForRevise(state.textEditingValue);
                            },
                          ),
                        );
                      }
                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: state.contextMenuAnchors,
                        buttonItems: buttons,
                      );
                    },
                  ),
                ),
              if (_reviseSelection != null) _buildRevisePanel(),
              if (_revising)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('正在改写选中段落…', style: TextStyle(fontSize: 12, color: AppColors.text2)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _outlineBusy ? null : _generateOutline,
                    child: Text(_outline.isEmpty ? '开始生成' : '重新生成'),
                  ),
                  const Spacer(),
                  Text(
                    _parsed.isEmpty ? '未识别到分集' : '已识别 ${_parsed.length} 个分集',
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: () => setState(() => _step = 1), child: const Text('上一步')),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _outlineBusy || _outline.trim().isEmpty ? null : _goChapters,
                child: const Text('确认大纲，进入章节生成'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _pickPassageForRevise(TextEditingValue value) {
    final start = value.selection.start;
    final end = value.selection.end;
    if (start < 0 || end <= start) return;
    setState(() {
      _reviseSelection = (start: start, end: end, passage: _outline.substring(start, end));
      _reviseInstruction = '';
      _reviseCtrl.clear();
    });
  }

  Widget _buildRevisePanel() {
    final selection = _reviseSelection!;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('选中段落 · ${selection.passage.length} 字', style: const TextStyle(fontSize: 12, color: AppColors.primary)),
          const SizedBox(height: 6),
          Text(selection.passage, style: const TextStyle(fontSize: 12.5, height: 1.7, color: AppColors.text2)),
          const SizedBox(height: 8),
          TextField(
            controller: _reviseCtrl,
            onChanged: (v) => _reviseInstruction = v,
            enabled: !_revising,
            decoration: const InputDecoration(hintText: '哪里不合理、希望怎么改（只改这一段）'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _revising ? null : () => setState(() => _reviseSelection = null),
                child: const Text('取消'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _revising || _reviseInstruction.trim().isEmpty ? null : _runRevise,
                child: Text(_revising ? '正在改写…' : '让 AI 改这一段'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runRevise() async {
    final selection = _reviseSelection;
    if (selection == null || _revising || _reviseInstruction.trim().isEmpty) return;
    setState(() => _revising = true);
    var start = selection.start;
    var end = selection.end;
    final original = _outline;
    try {
      final repo = ref.read(aiRepositoryProvider);
      final result = await repo.writeStream(
        prompt: outlineRevisePrompt(
          passage: selection.passage,
          instruction: _reviseInstruction.trim(),
          context: _outline.length > 1200 ? _outline.substring(0, 1200) : _outline,
        ),
        type: 'script',
        skillId: _skillId,
        model: _model,
        onDelta: (delta) {
          if (!mounted) return;
          setState(() {
            _outline = replaceTextRange(_outline, start, end, delta);
            end = start + delta.length;
          });
        },
      );
      if (!mounted) return;
      final text = cleanRevisedPassage(result.content);
      if (text.isEmpty) throw ApiException('AI 没有返回改写内容，请重试');
      setState(() {
        _outline = replaceTextRange(_outline, start, end, text);
        _reviseSelection = null;
        _reviseInstruction = '';
        _reviseCtrl.clear();
      });
      showAppToast(context, '这一段已按意见改写');
      ref.invalidate(welfareAssetProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 失败时还原原文，避免留下半截内容。
      setState(() => _outline = original);
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      } else if (mounted) {
        showAppToast(context, e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _outline = original);
        showAppToast(context, '改写失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _revising = false);
    }
  }

  Widget _buildChapters() {
    if (_creating) {
      return const _Card(
        child: Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      );
    }
    if (_createError.isNotEmpty) {
      return _Card(
        child: Column(
          children: [
            Text(_createError, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _ensureWork, child: const Text('重试')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle(
                '逐章生成',
                subtitle: _running
                    ? '生成中 $_generatedCount/${_chapters.where((c) => c.selected).length}'
                    : '已生成 $_generatedCount/${_chapters.length} 章，每章都已保存',
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 3, backgroundColor: AppColors.fill),
              ),
              const SizedBox(height: 12),
              if (_running && _runningIndex >= 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _stopping
                              ? '当前章写完后停止'
                              : '正在写「${_chapters[_runningIndex].title}」 · 已收到 ${_chapters[_runningIndex].streamingChars} 字',
                          style: const TextStyle(fontSize: 12, color: AppColors.text2),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Text('已勾选 $_selectedCount 章', style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                  const Spacer(),
                  if (!_running)
                    FilledButton(
                      onPressed: _selectedCount == 0 ? null : _startGeneration,
                      child: const Text('开始生成'),
                    )
                  else
                    OutlinedButton(
                      onPressed: _stopping ? null : () => setState(() => _stopping = true),
                      child: Text(_stopping ? '正在停止…' : '停止'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _chapters.length; i++) _chapterTile(i),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _running || _saving || _generatedCount == 0 ? null : _finishToWork,
          child: Text(_saving ? '正在保存…' : '进入作品工作台'),
        ),
      ],
    );
  }

  Widget _chapterTile(int index) {
    final task = _chapters[index];
    final tone = switch (task.state) {
      'generating' => AppColors.warning,
      'generated' => AppColors.success,
      'failed' => AppColors.danger,
      _ => AppColors.text3,
    };
    final label = switch (task.state) {
      'generating' => '生成中',
      'generated' => '已完成',
      'failed' => '生成失败',
      _ => '待生成',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r),
        side: BorderSide(color: tone.withOpacity(0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: task.selected,
                  onChanged: _running || task.state == 'generating'
                      ? null
                      : (v) => setState(() => task.selected = v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text1)),
                      if (task.recovered)
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Text('来自 AI 记录 · 进入工作台时保存', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                        ),
                      if (task.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(task.summary, style: const TextStyle(fontSize: 12, height: 1.6, color: AppColors.text2)),
                        ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: tone.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text(label, style: TextStyle(fontSize: 11, color: tone)),
                ),
              ],
            ),
            if (task.state == 'generating' && task.streaming.isNotEmpty)
              _PreviewBox(
                text: task.streaming.length > 600
                    ? task.streaming.substring(task.streaming.length - 600)
                    : task.streaming,
              ),
            if (task.state == 'failed')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(task.error, style: const TextStyle(fontSize: 12, color: AppColors.danger))),
                    TextButton(onPressed: _running ? null : () => _runChapter(task), child: const Text('重试本章')),
                  ],
                ),
              ),
            if (task.state == 'generated')
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text('查看正文 · ${task.content.length} 字', style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                children: [_PreviewBox(text: task.content)],
              ),
          ],
        ),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    const items = ['设定', '大纲', '章节'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: step == i + 1 ? AppColors.primaryTint : AppColors.fill,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${i + 1} ${items[i]}',
                style: TextStyle(
                  fontSize: 12,
                  color: step == i + 1 ? AppColors.primary : AppColors.text3,
                  fontWeight: step == i + 1 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text1)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text1, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(AppRadius.rSmall)),
      child: SingleChildScrollView(
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.8, color: AppColors.text2)),
      ),
    );
  }
}
