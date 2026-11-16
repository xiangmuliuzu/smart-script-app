import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../create/data/author_work_models.dart';
import '../../create/data/author_work_providers.dart';
import '../../welfare/data/welfare_providers.dart';
import '../ai_quota_dialog.dart';
import '../data/ai_providers.dart';
import '../data/ai_repository.dart';
import '../data/script_outline.dart';
import 'ai_model_selector.dart';
import 'ai_skill_selector.dart';

/// 写稿页内嵌 AI 创作面板（E 模块）。
///
/// 在章节写稿页正文编辑区上方展开，提供 AI 剧本 / 写作 / 润色 / 分镜四个功能 tab，
/// 复用 [AiRepository]（outline / write / polish / storyboard）生成，结果支持：
///   - 复制全文；
///   - [onInsert] 回调把生成内容插入当前章节正文（写作 / 润色 / 分镜 tab）；
///   - AI 剧本 tab 用「创建剧本大纲」把事件卡存进作品级剧本大纲（本机存档、可编辑），
///     再用「按大纲生成各章」按事件卡逐章生成正文写回章节；
///   - 「重新生成」两选一：完整重写，或提意见带着当前结果再生成。
/// 生成逻辑与独立 AI 功能页一致：次数不足弹引导弹窗、成功后刷新机会余额；
/// 可选择「导演(skill)」注入导演风格。
class AiInlinePanel extends ConsumerStatefulWidget {
  const AiInlinePanel({
    super.key,
    required this.onInsert,
    this.workId = 0,
    this.chapterId,
    this.chapterTitle,
    this.currentContent,
    this.previousChapter,
    this.previousSummaries,
    this.panelScroll,
  });

  /// 把生成文本插入当前章节正文。
  final ValueChanged<String> onInsert;

  /// 当前作品 id（剧本大纲按作品存档、按大纲生成各章需要写回章节）。
  final int workId;

  /// 当前章节 id（已保存过才有；插入正文后据此生成「本章摘要 + 台账」）。
  final int? chapterId;

  /// 当前章节标题（AI 续写时随提示词一起提交，与 PC 端一致）。
  final String Function()? chapterTitle;

  /// 当前章节已有正文（AI 续写时作为「已有正文」素材提交，与 PC 端一致）。
  final String Function()? currentContent;

  /// 上一章正文末尾（AI 续写承接锚点：让本集开头接得上上一集结尾）。
  final String Function()? previousChapter;

  /// 前情摘要（当前集之前最近几章的 chapter.summary，AI 续写时补跨章前情）。
  final String Function()? previousSummaries;

  /// 面板外层滚动控制器：生成完成后自动滚到底部，保证结果区可见。
  final ScrollController? panelScroll;

  @override
  ConsumerState<AiInlinePanel> createState() => _AiInlinePanelState();
}

enum _AiTab { outline, write, polish, storyboard }

class _AiInlinePanelState extends ConsumerState<AiInlinePanel> {
  _AiTab _tab = _AiTab.outline;
  int? _skillId;
  String? _model;

  // 大纲（与 PC 用户端一致：题材 + 集数 + 你的要求）
  final _inspiration = TextEditingController();
  // 故事灵感讲「讲什么」，你的要求讲「怎么写」，两个字段分开传给大纲接口。
  final _idea = TextEditingController();
  final _genre = TextEditingController();
  final _episodes = TextEditingController(text: '12');
  // 一集时长（分钟）：1 / 1.5 / 2，默认 1，与 PC 用户端同一口径。
  double _episodeMinutes = 1;

  // 写作
  final _prompt = TextEditingController();
  final _type = TextEditingController();

  // 润色
  final _content = TextEditingController();
  static const _polishStyles = ['简洁精炼', '专业正式', '文学优美', '轻松幽默', '情感细腻'];
  String? _selectedStyle;

  // 分镜（与独立 AI 分镜页一致：剧本文本 + 分镜风格）
  final _script = TextEditingController();
  static const _scriptStyles = ['电影感', '短剧竖屏', '动漫风'];
  String? _selectedScriptStyle;

  bool _loading = false;
  String _result = '';
  int _quotaUsed = 0;

  /// 作品级剧本大纲（本机存档，可在「创建剧本大纲」后编辑）。
  String _scriptOutline = '';

  /// 作品创作台账（后端读取，跨端共享）：人物卡 / 关系 / 伏笔 / 时间线 / 物品 / 线索。
  Map<String, String> _ledger = const {};

  /// 卷级状态快照（每 10 集一卷）：续写只注入「本卷 + 上卷」，替代整份台账。
  Map<int, String> _volumes = const {};

  @override
  void initState() {
    super.initState();
    // 本机大纲、后端台账、卷快照互不依赖，并行读取：任一读取失败都不影响续写。
    _loadOutline();
    _loadLedger();
    _loadVolumes();
  }

  Future<void> _loadOutline() async {
    try {
      final text = await loadScriptOutline(widget.workId);
      if (!mounted) return;
      if (text.isNotEmpty) setState(() => _scriptOutline = text);
    } catch (_) {
      // 本机大纲读不到不阻塞续写。
    }
  }

  /// 读取后端创作台账；读不到不影响续写（只是少一层上下文）。
  Future<void> _loadLedger() async {
    if (widget.workId <= 0) return;
    try {
      final ledger = await ref.read(aiRepositoryProvider).workLedger(widget.workId);
      if (!mounted) return;
      setState(() => _ledger = ledger);
    } catch (_) {
      // 台账未建或网络失败：静默跳过，不打断续写。
    }
  }

  /// 读取卷级状态快照；未生成或网络失败都静默跳过（回退台账注入）。
  Future<void> _loadVolumes() async {
    if (widget.workId <= 0) return;
    try {
      final volumes = await ref.read(aiRepositoryProvider).workVolumes(widget.workId);
      if (!mounted) return;
      setState(() => _volumes = volumes);
    } catch (_) {
      // 卷快照未生成或网络失败：不阻塞续写。
    }
  }

  @override
  void dispose() {
    _inspiration.dispose();
    _idea.dispose();
    _genre.dispose();
    _episodes.dispose();
    _prompt.dispose();
    _type.dispose();
    _content.dispose();
    _script.dispose();
    super.dispose();
  }

  /// 从标题里取集号（「第3集：xxx」/「第3章」）。
  static final RegExp _episodeNoPattern = RegExp(r'第\s*(\d{1,3})\s*[集章]');

  int? _episodeNo() {
    final title = (widget.chapterTitle?.call() ?? '').trim();
    final match = _episodeNoPattern.firstMatch(title);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  /// 本集事件卡：按集号优先、集名其次，从本机剧本大纲里切出。
  String _episodeCard() {
    final outline = _scriptOutline.trim();
    if (outline.isEmpty) return '';
    final episodes = parseScriptOutline(outline);
    if (episodes.isEmpty) return '';
    final title = (widget.chapterTitle?.call() ?? '').trim();
    final no = _episodeNo();
    ScriptOutlineEpisode? hit;
    for (final episode in episodes) {
      if (no != null && episode.no == no) {
        hit = episode;
        break;
      }
    }
    if (hit == null && title.isNotEmpty) {
      for (final episode in episodes) {
        if (episode.title.contains(title) || title.contains(episode.title)) {
          hit = episode;
          break;
        }
      }
    }
    if (hit == null) return '';
    return '${hit.label}\n${hit.body}';
  }

  /// 从「第5集：xxx」标题里取集号；取不到返回 0（此时所有线索只作背景，不会误判到期）。
  static int _episodeNoFromTitle(String title) {
    final match = RegExp(r'第\s*(\d{1,3})\s*集').firstMatch(title);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  /// 悬念排期：未解线索按「计划兑现点（第N集）」分成到期必须处理与未到期只能作背景。
  ///
  /// 长线悬念（如三年之约）不会因为已经写到下一集就被迫收线；
  /// 已结/已回收/已兑现的条目不再注入。兑现点取行内最后一个集号。
  static String _threadScheduleBlock(String threads, int currentNo) {
    final lines = threads
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';
    final due = <String>[];
    final later = <String>[];
    for (final raw in lines) {
      final line = raw.replaceFirst(RegExp(r'^(未解线索|线索)[：:]'), '').trim();
      if (line.isEmpty ||
          line.contains('已结') ||
          line.contains('已回收') ||
          line.contains('已兑现')) {
        continue;
      }
      final matches = RegExp(r'第\s*(\d{1,3})\s*集').allMatches(line).toList();
      final dueNo = matches.isEmpty
          ? 0
          : int.tryParse(matches.last.group(1) ?? '') ?? 0;
      if (dueNo > 0 && dueNo <= currentNo) {
        due.add(line);
      } else {
        later.add(line);
      }
    }
    final parts = <String>[];
    if (due.isNotEmpty) {
      parts.add('【本集必须处理（已到期未结的悬念/约定）】\n'
          '${due.map((line) => '- $line').join('\n')}\n'
          '这些项在本集必须给出进展或结果，不能整集不提；若本集事件卡没安排，'
          '就用一到两句交代推进到哪一步。');
    }
    if (later.isNotEmpty) {
      parts.add('【背景悬念（未到期，不得提前解决）】\n'
          '${later.map((line) => '- $line').join('\n')}\n'
          '这些项只需保持存在感（可提一句、可作动机），不得在本集提前收线或给出答案。');
    }
    return parts.join('\n\n');
  }

  /// 前情摘要块：当前集之前最近 6 章、合计 ≤1800 字（50 集量级下 4 章回溯不到上一卷）。
  static String _summaryBlock(List<AuthorChapterItem> chapters, int currentNo) {
    final list = chapters
        .where((chapter) =>
            chapter.chapterNo < currentNo && chapter.summary.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.chapterNo - b.chapterNo);
    if (list.isEmpty) return '';
    var text = '';
    for (final chapter in list.reversed.take(6)) {
      final line = '第${chapter.chapterNo}集：${chapter.summary.trim()}';
      final next = text.isEmpty ? line : '$line\n$text';
      if (next.length > 1800) break;
      text = next;
    }
    return text.isEmpty ? '' : '【前情摘要（已发生事实，勿重复交代）】\n$text';
  }

  /// 台账字段取尾部：台账是追加式，最新事实在末尾，从头截只会拿到第 1 集旧状态。
  static String _tailOf(String value, int max) =>
      value.length > max ? '（前略）${value.substring(value.length - max)}' : value;

  /// 台账块：六类各取尾部；按本集出场人物筛选人物卡与关系，其余四类全量。
  String _ledgerBlock({List<String> cast = const []}) {
    const labels = <String, String>{
      'characters': '本集出场人物',
      'relations': '相关关系',
      'foreshadow': '伏笔（埋在哪集/是否回收）',
      'timeline': '时间线',
      'items': '物品位置',
      'threads': '未解线索',
    };
    const budgets = <String, int>{
      'characters': 700,
      'relations': 400,
      'foreshadow': 300,
      'timeline': 250,
      'items': 250,
      'threads': 300,
    };
    String pick(String value, int max) {
      final lines = value
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (cast.isEmpty) return _tailOf(lines.join('\n'), max);
      final hit = lines.where((line) => cast.any((name) => line.contains(name))).join('\n');
      return _tailOf(hit.isEmpty ? lines.join('\n') : hit, max);
    }

    final lines = <String>[];
    for (final entry in labels.entries) {
      final value = (_ledger[entry.key] ?? '').trim();
      if (value.isEmpty) continue;
      lines.add('${entry.value}：\n${pick(value, budgets[entry.key] ?? 300)}');
    }
    if (lines.isEmpty) return '';
    return '【创作台账（已定事实，不得冲突）】\n${lines.join('\n')}';
  }

  /// 本集事件卡里的「本集出场：A、B」名单。
  List<String> _episodeCast(String card) {
    final match = RegExp(r'本集出场[：:]\s*(.+)').firstMatch(card);
    if (match == null) return const [];
    return (match.group(1) ?? '')
        .split(RegExp(r'[、，,／/；;]'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .take(6)
        .toList();
  }

  /// 卷快照块：本卷（当前事实）+ 上卷（仅背景），各 ≤800 字。
  String _volumeBlock() {
    if (_volumes.isEmpty) return '';
    final volumeNo = ((_episodeNo() ?? 1) + 9) ~/ 10;
    final parts = <String>[];
    final current = (_volumes[volumeNo] ?? '').trim();
    if (current.isNotEmpty) {
      parts.add('【本卷状态（第$volumeNo卷，当前事实以此为准）】\n${_tailOf(current, 800)}');
    }
    final previous = volumeNo > 1 ? (_volumes[volumeNo - 1] ?? '').trim() : '';
    if (previous.isNotEmpty) {
      parts.add('【上卷状态（第${volumeNo - 1}卷，仅作背景，不得与本卷冲突）】\n${_tailOf(previous, 800)}');
    }
    return parts.join('\n\n');
  }

  /// 组装 AI 续写提示词（与 PC 内嵌「AI 续写」同一口径）：
  /// 本集事件卡 + 创作台账 + 上一章末尾 + 本集已有正文 + 续写要求。
  /// 正文过长时只取末尾 1500 字作为承接上下文（压缩注入，给模型留足输出额度）。
  String _buildWritePrompt() {
    final prompt = _prompt.text.trim();
    final title = (widget.chapterTitle?.call() ?? '').trim();
    final content = (widget.currentContent?.call() ?? '').trim();
    final card = _episodeCard();
    final cast = _episodeCast(card);
    final ledger = _ledgerBlock(cast: cast);
    final schedule = _threadScheduleBlock(
      (_ledger['threads'] ?? '').trim(),
      _episodeNoFromTitle(title),
    );
    final volume = _volumeBlock();
    final summaries = (widget.previousSummaries?.call() ?? '').trim();
    final previous = (widget.previousChapter?.call() ?? '').trim();
    final parts = <String>[];
    if (title.isNotEmpty) parts.add(title);
    if (card.isNotEmpty) parts.add('【本集事件卡】\n$card');
    if (volume.isNotEmpty) parts.add(volume);
    if (summaries.isNotEmpty) parts.add(summaries);
    if (ledger.isNotEmpty) parts.add(ledger);
    if (schedule.isNotEmpty) parts.add(schedule);
    if (previous.isNotEmpty) {
      parts.add('【上一章末尾（承接语气与处境，勿重复）】\n$previous');
    }
    if (content.isNotEmpty) {
      final excerpt = content.length > 1500
          ? content.substring(content.length - 1500)
          : content;
      parts.add('【本集已有正文（从末尾接着写）】\n$excerpt');
    }
    parts.add('【续写要求】\n$prompt');
    return parts.join('\n\n');
  }

  /// 校验当前 tab 输入并生成（流式：逐块追加显示）。
  ///
  /// [feedback] 非空表示「提意见重新生成」：上一版结果与修改意见一起提交，
  /// 此时放宽必填校验（允许只给意见、不改原输入）。
  Future<void> _generate({String feedback = ''}) async {
    final feedbackMode = feedback.trim().isNotEmpty;
    final previous = _result.trim();
    if (feedbackMode && previous.isEmpty) {
      showAppToast(context, '当前没有可修改的生成结果，请先完整生成一次');
      return;
    }
    final requiredEmpty = switch (_tab) {
      _AiTab.outline =>
        _idea.text.trim().isEmpty && _inspiration.text.trim().isEmpty,
      _AiTab.write => _prompt.text.trim().isEmpty,
      _AiTab.polish => _content.text.trim().isEmpty,
      _AiTab.storyboard => _script.text.trim().isEmpty,
    };
    if (!feedbackMode && requiredEmpty) {
      final hint = switch (_tab) {
        _AiTab.outline => '请先填写故事灵感（或你的要求）',
        _AiTab.write => '请先输入续写要求',
        _AiTab.polish => '请先填写或粘贴需要润色的内容',
        _AiTab.storyboard => '请先填写或粘贴剧本文本',
      };
      showAppToast(context, hint);
      return;
    }
    // 集数口径与 PC 用户端一致：1–50 的整数（单部作品硬上限 50 集），默认 12。
    final episodes = int.tryParse(_episodes.text.trim()) ?? 0;
    if (!feedbackMode &&
        _tab == _AiTab.outline &&
        (episodes < 1 || episodes > 50)) {
      showAppToast(context, '集数需为 1–50 的整数');
      return;
    }
    final episodeCount = (episodes >= 1 && episodes <= 50) ? episodes : 12;

    setState(() {
      _loading = true;
      _result = '';
      _quotaUsed = 0;
    });
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final repo = ref.read(aiRepositoryProvider);
      void onDelta(String delta) {
        if (!mounted) return;
        setState(() => _result += delta);
      }

      String text;
      String? emptyHint;
      // 上游 finish_reason=length 时后端下发 truncated=true：正文停在半句，要提示重试
      var truncated = false;
      switch (_tab) {
        case _AiTab.outline:
          final ideaText = _idea.text.trim();
          final askText = _inspiration.text.trim();
          final brief = [
            if (ideaText.isNotEmpty) '故事灵感：\n$ideaText',
            if (askText.isNotEmpty) '写法要求：\n$askText',
          ].join('\n');
          final core = feedbackMode
              ? '$brief\n上一版大纲（大体满意，请在保留整体结构与事件走向的前提下按修改意见调整）：\n'
                  '${previous.length > 12000 ? previous.substring(0, 12000) : previous}\n'
                  '修改意见：${feedback.trim()}'
              : brief;
          final minuteLabel =
              _episodeMinutes == 1.5 ? '1.5 分钟' : '${_episodeMinutes.toInt()} 分钟';
          final result = await repo.outlineStream(
            inspiration: '$core\n'
                '请按下面格式写 $episodeCount 集分集事件卡，从第1集起连续编号：\n'
                '第1集：事件名\n本集事件：……\n冲突与推进：……\n'
                '结果或反转：……\n结尾钩子：……\n'
                '每集是一件完整的事（有开场、交锋、结果），结尾钩子要具体；'
                '不要写场景头、镜号、景别、运镜。\n'
                '每集按一集 $minuteLabel 的短剧容量写：一集只承载一个场景或一次交锋，'
                '不要塞进多天多地的内容。',
            genre: _genre.text.trim(),
            style: '共 $episodeCount 集，每集 $minuteLabel',
            skillId: _skillId,
            model: _model,
            onDelta: onDelta,
          );
          text = result.outlineText;
          _quotaUsed = result.quotaUsed;
          if (text.trim().isEmpty) emptyHint = '未生成剧本大纲，请重试';
          break;
        case _AiTab.write:
          final promptText = feedbackMode
              ? '上一版正文：\n$previous\n修改意见：${feedback.trim()}\n'
                  '请按修改意见重写这一集：700-900 字，只写这一集，结尾留具体钩子。'
              : _buildWritePrompt();
          // 规则版生成后核查（模型档暂缓）：只提示，不阻断。
          if (!feedbackMode &&
              _scriptOutline.trim().isNotEmpty &&
              _episodeCard().isEmpty) {
            showAppToast(context, '生成后核查：大纲里没找到本集事件卡，续写可能偏离大纲，建议先在大纲里补齐本集');
          }
          final result = await repo.writeStream(
            prompt: promptText,
            type: _type.text.trim(),
            skillId: _skillId,
            model: _model,
            onDelta: onDelta,
          );
          text = result.content;
          truncated = result.truncated;
          if (text.trim().isEmpty) emptyHint = '未生成内容，请重试';
          if (mounted && text.trim().isNotEmpty && text.trim().length < 500) {
            showAppToast(context, '生成后核查：本集正文不足 500 字，建议补写完整事件与结尾钩子');
          }
          break;
        case _AiTab.polish:
          final contentText = feedbackMode
              ? '原文：\n${_content.text.trim()}\n上一版润色结果：\n$previous\n'
                  '修改意见：${feedback.trim()}\n请输出修改后的完整文本。'
              : _content.text.trim();
          final result = await repo.polishStream(
            content: contentText,
            style: _selectedStyle,
            skillId: _skillId,
            model: _model,
            onDelta: onDelta,
          );
          text = result.content;
          truncated = result.truncated;
          if (text.trim().isEmpty) emptyHint = '未生成润色结果，请重试';
          break;
        case _AiTab.storyboard:
          final scriptText = feedbackMode
              ? '剧本文本：\n${_script.text.trim()}\n上一版分镜：\n$previous\n'
                  '修改意见：${feedback.trim()}\n请保持场次与镜号结构重写分镜。'
              : _script.text.trim();
          final result = await repo.storyboardStream(
            script: scriptText,
            style: _selectedScriptStyle,
            skillId: _skillId,
            model: _model,
            onDelta: onDelta,
          );
          text = result.content;
          truncated = result.truncated;
          if (text.trim().isEmpty) emptyHint = '未生成分镜，请重试';
          break;
      }
      // 扣减已发生：刷新机会余额缓存（写稿页无次数展示，福利中心/创作页仍监听）。
      container.invalidate(aiBalanceProvider);
      container.invalidate(welfareAssetProvider);
      if (!mounted) return;
      if (emptyHint != null) showAppToast(context, emptyHint);
      if (truncated) showAppToast(context, '输出被判截断，请重试');
      setState(() => _result = text);
      _scrollToResult();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isQuotaInsufficientError(e)) {
        showAiQuotaInsufficientDialog(context, message: e.message);
      } else {
        showAppToast(context, e.message);
      }
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 生成结果落在面板底部：外层可滚动时自动滚到底，避免结果区看不到。
  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = widget.panelScroll;
      if (controller == null || !controller.hasClients) return;
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _copy() {
    if (_result.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _result));
    showAppToast(context, '内容已复制');
  }

  void _insert() {
    if (_result.trim().isEmpty) return;
    widget.onInsert(_result);
    showAppToast(context, '已插入章节正文');
    _syncChapterSummary();
  }

  /// 方案 2：正文插入后单独调一次 AI，产出「本章摘要 + 台账更新」由后端落库；正文不变。
  /// 只在章节已保存过（有 chapterId）时触发；失败只提示，不影响正文。
  Future<void> _syncChapterSummary() async {
    final workId = widget.workId;
    final chapterId = widget.chapterId;
    if (workId <= 0 || chapterId == null || chapterId <= 0) return;
    final content = (widget.currentContent?.call() ?? '').trim();
    if (content.length < 50) return;
    if (mounted) showAppToast(context, '正在生成本章摘要，约半分钟…');
    try {
      await ref.read(aiRepositoryProvider).summarizeChapter(
        workId: workId,
        chapterId: chapterId,
        content: content,
      );
      // 摘要落库后刷新作品详情，下一章注入的「前情摘要」才会立刻用上这一条。
      ref.invalidate(authorWorkDetailProvider(workId));
      if (mounted) showAppToast(context, '已更新本章摘要与创作台账');
      await _reviewChapter(workId, chapterId, content);
      await _snapshotVolumeAtEnd(workId);
    } catch (_) {
      if (mounted) showAppToast(context, '摘要未更新，可稍后重试');
    }
  }

  /// 每集验收：不通过只提示，不改正文。
  Future<void> _reviewChapter(int workId, int chapterId, String content) async {
    try {
      final review = await ref.read(aiRepositoryProvider).reviewChapter(
            workId: workId,
            chapterId: chapterId,
            content: content,
          );
      if (!mounted) return;
      final pass = review['pass'] == true;
      final score = review['score'] ?? 0;
      final issues = (review['issues'] ?? '').toString().trim();
      showAppToast(context, pass ? '本集验收通过（$score/5）' : '本集验收 $score/5，建议重写：$issues');
    } catch (_) {
      if (mounted) showAppToast(context, '验收未完成，可稍后重试');
    }
  }

  /// 卷末（第 10/20/30…集）生成卷级快照，下一卷续写改用「本卷 + 上卷」注入。
  Future<void> _snapshotVolumeAtEnd(int workId) async {
    final no = _episodeNo();
    if (no == null || no == 0 || no % 10 != 0) return;
    final volumeNo = (no + 9) ~/ 10;
    try {
      await ref.read(aiRepositoryProvider).buildVolumeSnapshot(
            workId: workId,
            volumeNo: volumeNo,
          );
      await _loadVolumes();
      if (mounted) showAppToast(context, '已生成第$volumeNo卷状态快照');
    } catch (_) {
      if (mounted) showAppToast(context, '第$volumeNo卷快照未生成，可稍后重试');
    }
  }

  /// 重新生成：两选一（完整重写 / 提意见带着当前结果再生成）。
  Future<void> _regenerate() async {
    if (_result.trim().isEmpty) {
      showAppToast(context, '还没有生成结果，请先完整生成一次');
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('重新生成会覆盖当前结果，选择生成方式：',
                    style: TextStyle(fontSize: 12, color: AppColors.text3)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: AppColors.primary),
              title: const Text('完整重新生成'),
              subtitle: const Text('忽略当前结果，按上面的要求重新写一版'),
              onTap: () => Navigator.pop(sheetContext, 'full'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note, color: AppColors.primary),
              title: const Text('提意见重新生成'),
              subtitle: const Text('大体满意，写清要改哪里，AI 带着当前结果改'),
              onTap: () => Navigator.pop(sheetContext, 'feedback'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'full') {
      await _generate();
      return;
    }
    if (action != 'feedback') return;
    final feedback = await _askFeedback();
    if (!mounted || feedback == null || feedback.trim().isEmpty) return;
    await _generate(feedback: feedback);
  }

  /// 弹出修改意见输入框，返回用户填写的意见。
  Future<String?> _askFeedback() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('提意见重新生成', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('写下修改意见，会和当前生成结果一起提交给 AI：',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '例如：第 3 集冲突不够，人物动机要更明确',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('按意见重新生成'),
          ),
        ],
      ),
    );
    controller.dispose();
    return text;
  }

  /// 把当前 AI 剧本结果存进作品级剧本大纲（已有不同内容时先确认覆盖）。
  /// 故事简介、主要人物、人物关系属于创作资料，不写进大纲，只存分集事件卡。
  Future<void> _createOutline() async {
    final text = _result.trim();
    if (text.isEmpty) {
      showAppToast(context, '还没有生成结果，请先完整生成一次');
      return;
    }
    final outlineText = extractOutlineOnly(text);
    if (outlineText.isEmpty) {
      showAppToast(context, '结果里没有识别到「第N集：事件名」的分集事件卡，请重新生成');
      return;
    }
    if (widget.workId <= 0) {
      showAppToast(context, '未识别作品，无法保存剧本大纲');
      return;
    }
    final saved = _scriptOutline.trim();
    if (saved.isNotEmpty && saved != outlineText) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('覆盖剧本大纲'),
          content: const Text('剧本大纲里已有内容，覆盖后原内容不再保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
    }
    await saveScriptOutline(widget.workId, outlineText);
    if (!mounted) return;
    setState(() => _scriptOutline = outlineText);
    await _editOutline();
  }

  /// 编辑并保存本机剧本大纲（存好即可直接按它生成各章）。
  Future<void> _editOutline() async {
    final controller = TextEditingController(text: _scriptOutline);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('剧本大纲', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              hintText: '第1集：事件名\n本集事件：……\n冲突与推进：……\n结果或反转：……\n结尾钩子：……',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存大纲'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || text == null) return;
    await saveScriptOutline(widget.workId, text);
    if (!mounted) return;
    setState(() => _scriptOutline = text.trim());
    showAppToast(context, '剧本大纲已保存');
  }

  /// 按大纲生成各章：来源二选一（当前输出 / 已保存的剧本大纲），只补空章节。
  Future<void> _fillOutline() async {
    var source = _result.trim();
    if (_scriptOutline.trim().isNotEmpty) {
      final useSaved = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('用哪一份大纲生成各章？「剧本大纲」是可保存、可修改的版本。',
                      style: TextStyle(fontSize: 12, color: AppColors.text3)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.notes, color: AppColors.primary),
                title: const Text('用当前输出'),
                subtitle: const Text('本次 AI 生成的结果'),
                onTap: () => Navigator.pop(sheetContext, false),
              ),
              ListTile(
                leading: const Icon(Icons.bookmark, color: AppColors.primary),
                title: const Text('用剧本大纲'),
                subtitle: const Text('已保存、可修改的剧本大纲'),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (!mounted || useSaved == null) return;
      if (useSaved) source = _scriptOutline.trim();
    }
    if (source.isEmpty) {
      showAppToast(context, '还没有可用的大纲，请先生成剧本大纲');
      return;
    }
    if (widget.workId <= 0) {
      showAppToast(context, '未识别作品，无法生成各章');
      return;
    }
    final episodes = parseScriptOutline(source);
    if (episodes.isEmpty) {
      showAppToast(context, '没识别出分集标题，请确认大纲里有「第1集：事件名」这样的标题行');
      return;
    }
    final chapters = ref
            .read(authorWorkDetailProvider(widget.workId))
            .valueOrNull
            ?.chapters ??
        const <AuthorChapterItem>[];
    final byNo = <int, AuthorChapterItem>{};
    for (final chapter in chapters) {
      byNo[chapter.chapterNo] = chapter;
    }
    final targets = <ScriptOutlineEpisode>[];
    for (final ep in episodes) {
      final chapter = byNo[ep.no];
      if (chapter == null || chapter.content.trim().isEmpty) targets.add(ep);
    }
    if (targets.isEmpty) {
      showAppToast(context, '这些集都已有正文，没有需要生成的空章节');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('按大纲生成各章'),
        content: Text(
          '将生成 ${targets.length} 章：'
          '${targets.map((ep) => '第${ep.no}集').join('、')}。'
          '仅补空正文章节，每章按实际 token 扣除积分。',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('开始生成'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _loading = true);
    var done = 0;
    var failed = 0;
    try {
      final repo = ref.read(aiRepositoryProvider);
      final workRepo = ref.read(authorWorkRepositoryProvider);
      for (final ep in targets) {
        if (!mounted) return;
        try {
          // 与 PC「按大纲生成各章」同口径：事件卡 + 前情摘要 + 台账。
          final summaryText = _summaryBlock(chapters, ep.no);
          final ledgerText = _ledgerBlock();
          final scheduleText = _threadScheduleBlock(
            (_ledger['threads'] ?? '').trim(),
            ep.no,
          );
          final prompt = '${ep.label}\n${ep.body}\n'
              '请据此事件卡写这一集的正文：700-900 字，开头一句自然交代地点时间，'
              '动作与对白推进，对白用「角色：台词」，只写这一集，结尾留具体钩子，'
              '不写场景头、镜号、景别、运镜。'
              + (summaryText.isEmpty ? '' : '\n\n$summaryText')
              + (ledgerText.isEmpty ? '' : '\n\n$ledgerText')
              + (scheduleText.isEmpty ? '' : '\n\n$scheduleText');
          final result = await repo.writeStream(
            prompt: prompt,
            skillId: _skillId,
            model: _model,
            onDelta: (_) {},
          );
          final body = result.content.trim();
          if (body.isEmpty) {
            failed++;
            continue;
          }
          final chapter = byNo[ep.no];
          if (chapter != null) {
            await workRepo.updateChapter(chapter.chapterId, content: body);
          } else {
            await workRepo.addChapter(
              widget.workId,
              chapterNo: ep.no,
              chapterTitle: ep.title,
              content: body,
            );
          }
          done++;
        } catch (_) {
          failed++;
        }
      }
      ref.invalidate(authorWorkDetailProvider(widget.workId));
      if (!mounted) return;
      showAppToast(
          context, '已生成 $done 章${failed > 0 ? '，$failed 章失败' : ''}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 积分余额（与 PC 用户端一致：AI 创作旁展示剩余积分）。
    final asset = ref.watch(welfareAssetProvider);
    final pointsText = asset.when(
      loading: () => '积分 —',
      error: (_, __) => '积分 —',
      data: (value) => '积分 ${value.points.balance}',
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text('AI 创作',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const Spacer(),
              Text(pointsText,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const SizedBox(width: 12),
              // AI 记录入口：记录内容多，内嵌展示不便，直接跳转记录页。
              InkWell(
                onTap: () => context.push(RoutePath.aiRecords),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('AI 记录',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text1)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _tabChip(_AiTab.outline, '剧本'),
              const SizedBox(width: 6),
              _tabChip(_AiTab.write, '续写'),
              const SizedBox(width: 6),
              _tabChip(_AiTab.polish, '润色'),
              const SizedBox(width: 6),
              _tabChip(_AiTab.storyboard, '分镜'),
            ],
          ),
          const SizedBox(height: 10),
          AiSkillSelector(
            selectedSkillId: _skillId,
            onChanged: (value) => setState(() => _skillId = value),
            enabled: !_loading,
            skillTypeFilter: _tab == _AiTab.storyboard ? 'storyboard' : 'write',
          ),
          const SizedBox(height: 10),
          AiModelSelector(
            selectedModel: _model,
            onChanged: (value) => setState(() => _model = value),
            enabled: !_loading,
          ),
          const SizedBox(height: 10),
          _buildForm(),
          if (_result.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.fill,
                borderRadius: BorderRadius.circular(AppRadius.rSmall),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _result,
                  style: const TextStyle(
                      fontSize: 13, height: 1.6, color: AppColors.text2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_quotaUsed > 0)
                  Text('消耗 $_quotaUsed token',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.text3)),
                if (_tab == _AiTab.outline) ...[
                  _actionButton(
                    label: '按大纲生成各章',
                    icon: Icons.auto_fix_high,
                    onPressed: _fillOutline,
                  ),
                  _actionButton(
                    label: '创建剧本大纲',
                    icon: Icons.bookmark_add_outlined,
                    onPressed: _createOutline,
                  ),
                ] else
                  _actionButton(
                    label: '插入正文',
                    icon: Icons.south_west,
                    onPressed: _insert,
                  ),
                _outlineButton(
                  label: '重新生成',
                  icon: Icons.refresh,
                  onPressed: _regenerate,
                ),
                _outlineButton(
                  label: '复制',
                  icon: Icons.copy,
                  onPressed: _copy,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 结果区主按钮（实心），统一禁用态与尺寸。
  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: _loading ? null : onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// 结果区次按钮（描边）。
  Widget _outlineButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text1,
        side: const BorderSide(color: AppColors.primary),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// tab 切换小按钮。
  Widget _tabChip(_AiTab tab, String label) {
    final selected = _tab == tab;
    return InkWell(
      onTap: _loading
          ? null
          : () => setState(() {
                _tab = tab;
                _result = '';
                _quotaUsed = 0;
              }),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.text1 : AppColors.text2,
          ),
        ),
      ),
    );
  }

  /// 当前 tab 的输入表单（按功能不同渲染）。
  Widget _buildForm() {
    final Widget form = switch (_tab) {
      _AiTab.outline => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_idea, '故事灵感', 4, '这个故事大体讲了什么：谁、在什么处境、要解决什么…'),
            const SizedBox(height: 10),
            _field(_inspiration, '你的要求', 4, '写法上的要求，例如：节奏必须紧凑，前三集埋一个反转…'),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(_genre, '题材（可选）', 1, '例如：都市情感'),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 84,
                  child: _field(
                    _episodes,
                    '集数',
                    1,
                    '12',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(width: 120, child: _durationField()),
            if (_scriptOutline.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: _outlineButton(
                  label: '按当前剧本大纲生成各章',
                  icon: Icons.list_alt,
                  onPressed: _fillOutline,
                ),
              ),
            ],
          ],
        ),
      _AiTab.write => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_prompt, '续写要求 *', 4, '例如：接着写下一段，男主与对手在雨夜对峙'),
            const SizedBox(height: 10),
            _field(_type, '续写侧重（可选）', 1, '例如：对话、旁白、动作描写'),
          ],
        ),
      _AiTab.polish => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_content, '待润色内容 *', 4, '粘贴需要润色的正文、对话或旁白'),
            const SizedBox(height: 10),
            const Text('选择风格',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in _polishStyles)
                  _styleChip(style),
              ],
            ),
          ],
        ),
      _AiTab.storyboard => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_script, '剧本文本 *', 4, '粘贴 AI 剧本或自写剧本，AI 将拆解为可出售的分镜脚本'),
            const SizedBox(height: 10),
            const Text('选择分镜风格',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in _scriptStyles)
                  InkWell(
                    onTap: () => setState(() {
                      _selectedScriptStyle =
                          (_selectedScriptStyle == style ? null : style);
                    }),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedScriptStyle == style
                            ? AppColors.primary
                            : AppColors.fill,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selectedScriptStyle == style
                              ? AppColors.primary
                              : AppColors.divider,
                        ),
                      ),
                      child: Text(
                        style,
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedScriptStyle == style
                              ? Colors.white
                              : AppColors.text2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        form,
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: _loading ? null : _generate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.rSmall),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('生成',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int maxLines,
    String hint, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
            filled: true,
            fillColor: AppColors.fill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            isDense: true,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          style: const TextStyle(fontSize: 13, color: AppColors.text1),
        ),
      ],
    );
  }

  /// 「一集时长」下拉：1 / 1.5 / 2 分钟，默认 1 分钟，与 PC 用户端同一口径。
  Widget _durationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('一集时长',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
        const SizedBox(height: 6),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(AppRadius.rSmall),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: _episodeMinutes,
              isDense: true,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down,
                  size: 18, color: AppColors.text2),
              style: const TextStyle(fontSize: 13, color: AppColors.text1),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 分钟')),
                DropdownMenuItem(value: 1.5, child: Text('1.5 分钟')),
                DropdownMenuItem(value: 2, child: Text('2 分钟')),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _episodeMinutes = value ?? 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _styleChip(String style) {
    final selected = _selectedStyle == style;
    return InkWell(
      onTap: () => setState(() {
        _selectedStyle = selected ? null : style;
      }),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          style,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
