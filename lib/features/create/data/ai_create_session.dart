import 'dart:convert';

import '../../ai/data/ai_models.dart';

/// AI 创作页生成的章节正文记录标记（与 PC 创作者端一致）。
///
/// 写进 sys_ai_write_record.input_prompt 前缀，用来把「一次 AI 创作」的大纲与
/// 它生成的章节正文归到一起；工作台等其他入口生成的正文没有标记，保持各自单条。
const String kAiCreateMark = '[AI创作]';

/// 换行常量（避免字符串模板里写换行被工具转义）。
final String kAiCreateBreak = String.fromCharCode(10);

/// 给章节正文 prompt 打上 AI 创作标记。
String markAiCreatePrompt(String prompt) => '$kAiCreateMark ${prompt.trim()}';

/// 一次 AI 创作（大纲记录 + 它之后生成的章节记录）。
class AiCreateSession {
  const AiCreateSession({
    required this.outlineRecord,
    this.chapters = const [],
  });

  final AiWriteRecord outlineRecord;
  final List<AiWriteRecord> chapters;

  String get id => 'outline-${outlineRecord.recordId}';

  /// 大纲请求的原始输入（灵感：…／类型：…／风格：…）。
  String get input => outlineRecord.inputPrompt;

  /// 还原后的书名、灵感、题材与集数。
  AiCreateSetup get setup => AiCreateSetup.parse(outlineRecord.inputPrompt);

  String get outline => outlineRecord.outputContent;

  /// 本次所有记录（大纲 + 章节），供记录管理整组删除。
  List<AiWriteRecord> get records => [outlineRecord, ...chapters];

  int get tokens => records.fold(0, (sum, r) => sum + r.tokensUsed);

  String get createdAt => outlineRecord.createdAt;
}

/// 从大纲记录输入里还原 AI 创作页的设定。
class AiCreateSetup {
  const AiCreateSetup({
    this.title = '',
    this.idea = '',
    this.genre = '',
    this.episodes = 12,
  });

  final String title;
  final String idea;
  final String genre;
  final int episodes;

  bool get isEmpty => title.isEmpty && idea.isEmpty;

  /// 解析「灵感：书名：… ↵ 故事灵感：… ↵ 请提供 N 个分集 ↵ 类型：… ↵ 风格：…」；
  /// 不是 PC/AI 创作页格式时返回 null。
  static AiCreateSetup? tryParse(String input) {
    if (!input.contains('灵感：')) return null;
    final lines = const LineSplitter().convert(input);
    final firstIndex = lines.indexWhere((l) => l.startsWith('灵感：'));
    if (firstIndex < 0) return null;
    final inspirationLines = <String>[lines[firstIndex].substring('灵感：'.length)];
    for (var i = firstIndex + 1; i < lines.length; i++) {
      if (lines[i].startsWith('类型：') || lines[i].startsWith('风格：')) break;
      inspirationLines.add(lines[i]);
    }
    final inspiration = inspirationLines.join('\n');
    final title = RegExp(r'书名：(.+)').firstMatch(inspiration)?.group(1)?.trim() ?? '';
    final idea = (inspiration.split('故事灵感：').length > 1
            ? inspiration.split('故事灵感：')[1]
            : '')
        .split('请提供')
        .first
        .trim();
    if (title.isEmpty && idea.isEmpty) return null;
    final genreLine = lines.firstWhere((l) => l.startsWith('类型：'), orElse: () => '');
    final episodeMatch = RegExp(r'请提供\s*(\d+)\s*个分集').firstMatch(inspiration) ??
        RegExp(r'共\s*(\d+)\s*集').firstMatch(input);
    final episodes = int.tryParse(episodeMatch?.group(1) ?? '') ?? 12;
    return AiCreateSetup(
      title: title,
      idea: idea,
      genre: genreLine.isEmpty ? '' : genreLine.substring('类型：'.length).trim(),
      episodes: episodes > 0 ? episodes : 12,
    );
  }

  static AiCreateSetup parse(String input) => tryParse(input) ?? const AiCreateSetup();
}

/// 从章节正文 prompt 里取出章节标题（与 PC「按大纲生成各章」同一措辞）。
String chapterTitleFromPrompt(String prompt) =>
    RegExp(r'为“(.+?)”创作正文').firstMatch(prompt)?.group(1)?.trim() ?? '';

/// 合并 AI 记录：大纲记录 + 它之后生成的（带 [AI创作] 标记）章节记录算一条。
///
/// [records] 按时间倒序传入。返回按时间倒序的会话列表；不属于任何大纲的记录忽略，
/// 由页面按原来的单条样式展示。
List<AiCreateSession> groupAiCreateRecords(List<AiWriteRecord> records) {
  final outlines = records
      .where((r) => r.writeType == 'outline' && AiCreateSetup.tryParse(r.inputPrompt) != null)
      .toList();
  if (outlines.isEmpty) return const [];
  final ownerOf = <int, AiWriteRecord>{};
  for (final record in records) {
    if (record.writeType != 'write' || !record.outputContent.startsWith(kAiCreateMark)) {
      continue;
    }
    final candidates = outlines
        .where((o) => o.recordId == 0 || record.recordId == 0 || o.recordId < record.recordId)
        .toList()
      ..sort((a, b) => b.recordId.compareTo(a.recordId));
    if (candidates.isNotEmpty) ownerOf[record.recordId] = candidates.first;
  }
  final sessions = <AiCreateSession>[];
  for (final outline in outlines) {
    final chapters = records
        .where((r) => ownerOf[r.recordId]?.recordId == outline.recordId)
        .toList()
      ..sort((a, b) => a.recordId.compareTo(b.recordId));
    sessions.add(AiCreateSession(outlineRecord: outline, chapters: chapters));
  }
  sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sessions;
}

/// 从可读大纲文本里取一段作品简介（优先「一句话简介 / 简介」行）。
String outlineSummaryText(String text, {int limit = 200}) {
  final lines = const LineSplitter()
      .convert(text)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final labelMatch = RegExp(r'^(?:一句话简介|剧情简介|故事简介|简介)\s*[:：]\s*(.+)');
  String picked = '';
  for (final line in lines) {
    final m = labelMatch.firstMatch(line.replaceFirst(RegExp(r'^[-*]\s*'), ''));
    if (m != null) {
      picked = m.group(1)!.trim();
      break;
    }
  }
  if (picked.isEmpty) {
    picked = lines.firstWhere(
      (l) => !RegExp(r'^(?:书名|角色|人物|题材|风格|主题|背景设定|世界观|结局)\s*[:：]').hasMatch(l) &&
          !RegExp(r'^第\s*[\d一二三四五六七八九十百千]+\s*[章节節集回]').hasMatch(l),
      orElse: () => '',
    );
  }
  picked = picked.replaceFirst(RegExp(r'^[-*]\s*'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return picked.length > limit ? picked.substring(0, limit) : picked;
}

/// 按大纲文本宽松识别已出现的分集标题（流式进度用，允许概要未写完）。
List<String> listOutlineEpisodeTitles(String text) {
  final titles = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    final heading = raw.trim().replaceFirst(RegExp(r'^#{1,6}\s*'), '').replaceAll(RegExp(r'^\*\*(.*?)\*\*$'), r'$1');
    if (heading.isEmpty) continue;
    if (RegExp(r'^(?:第\s*[\d零〇一壹二两兩贰貳三叁參四肆五伍六陆陸七柒八捌九玖十拾百佰千仟]+\s*[章节節集回]|[\d零〇一壹二两兩贰貳三叁參四肆五伍六陆陸七柒八捌九玖十拾百佰千仟]+\s*[.、:：)）])').hasMatch(heading)) {
      titles.add(heading.replaceFirst(RegExp(r'[：:]\s*$'), ''));
    }
  }
  return titles;
}

/// 严格分章（用于确认大纲后建章）：每集必须有标题，概要取标题之后的文本。
List<AiCreateChapterSeed> parseOutlineChapters(String text) {
  final seeds = <AiCreateChapterSeed>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim().replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    if (line.isEmpty) continue;
    if (listOutlineEpisodeTitles(line).isNotEmpty) {
      seeds.add(AiCreateChapterSeed(title: line.replaceFirst(RegExp(r'[：:]\s*$'), '')));
    } else if (seeds.isNotEmpty) {
      final last = seeds.last;
      seeds[seeds.length - 1] = AiCreateChapterSeed(
        title: last.title,
        summary: last.summary.isEmpty ? line : last.summary + kAiCreateBreak + line,
      );
    }
  }
  return seeds.where((s) => s.title.isNotEmpty).toList();
}

/// 大纲里解析出的一集（标题 + 概要）。
class AiCreateChapterSeed {
  const AiCreateChapterSeed({required this.title, this.summary = ''});
  final String title;
  final String summary;
}

/// 从「AI 记录」带回 AI 创作页的草稿：设定 + 大纲 + 已生成章节（只作预览）。
class AiCreateDraft {
  const AiCreateDraft({
    this.title = '',
    this.idea = '',
    this.genre = '',
    this.episodes = 12,
    this.outline = '',
    this.chapters = const [],
  });

  final String title;
  final String idea;
  final String genre;
  final int episodes;
  final String outline;
  final List<AiCreateDraftChapter> chapters;
}

/// 恢复的章节（标题 + 正文）。
class AiCreateDraftChapter {
  const AiCreateDraftChapter({required this.title, required this.content});
  final String title;
  final String content;
}

/// 大纲局部改写提示词：只重写选中段落，保持分集格式与前后衔接。
String outlineRevisePrompt({
  required String passage,
  required String instruction,
  required String context,
}) =>
    [
      '下面是一份剧本大纲中的一段内容，作者认为这部分不合理，请按作者意见只重写这一段。',
      '要求：保持分集编号与标题格式（如「第一集：章节名称」）、保持与其他分集的前后衔接；只输出重写后的这一段文字，不要输出整份大纲，不要解释、不要前后缀、不要 Markdown。',
      '',
      '【大纲上下文（仅供理解，不要重写）】',
      context.isEmpty ? '（无）' : context,
      '',
      '【需要重写的段落】',
      passage,
      '',
      '【作者意见】',
      instruction,
    ].join(kAiCreateBreak);

/// 用新文本替换 [start, end) 区间，返回替换后的整段文本。
String replaceTextRange(String text, int start, int end, String replacement) {
  final safeStart = start < 0 ? 0 : (start > text.length ? text.length : start);
  final safeEnd = end < safeStart ? safeStart : (end > text.length ? text.length : end);
  return text.substring(0, safeStart) + replacement + text.substring(safeEnd);
}

/// 去掉改写结果里模型偶尔带回的代码块围栏或引号包裹。
String cleanRevisedPassage(String raw) {
  var text = raw.trim();
  final fence = String.fromCharCodes([96, 96, 96]);
  if (text.startsWith(fence)) {
    final firstBreak = text.indexOf(kAiCreateBreak);
    text = firstBreak < 0 ? '' : text.substring(firstBreak + 1);
  }
  if (text.endsWith(fence)) text = text.substring(0, text.length - fence.length);
  return text.replaceAll(RegExp(r'^["“]|["”]$'), '').trim();
}
