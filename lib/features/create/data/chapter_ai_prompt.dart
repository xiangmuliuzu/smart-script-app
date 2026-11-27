/// 章节页「AI 创作」弹层的提示词拼装（纯函数，便于单元测试）。
///
/// 与 PC 创作者端 `studioWritePrompt` / `studioStoryboardScript` 同口径：
/// 参考资料按「参考范围」chips 选择性注入，作者要求追加在最后；
/// 生成结果只预览，用户确认后才写回章节。
library;

import 'blueprint_models.dart';

String _clean(String value) => value.trim();

/// 上一章末尾截取（避免吃掉模型输出额度）。
String chapterTail(String content, {int limit = 800}) {
  final text = content.trim();
  if (text.length <= limit) return text;
  return text.substring(text.length - limit);
}

/// 创作台账 → 提示词块：只取与本章出场人物相关的人物/关系行，控制长度。
String ledgerPromptBlock(
  WorkLedger? ledger, {
  List<String> castNames = const [],
  int limit = 1600,
}) {
  if (ledger == null) return '';
  String pick(String value, int max) {
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';
    final hits = castNames.isEmpty
        ? lines
        : lines.where((line) => castNames.any((name) => line.contains(name))).toList();
    final text = (hits.isEmpty ? lines : hits).join('\n');
    return text.length > max ? text.substring(text.length - max) : text;
  }

  final blocks = <String>[
    if (_clean(ledger.storySummary).isNotEmpty)
      '故事简介：\n${pick(ledger.storySummary, 600)}',
    if (_clean(ledger.characters).isNotEmpty)
      '主要人物：\n${pick(ledger.characters, 800)}',
    if (_clean(ledger.relations).isNotEmpty)
      '人物关系：\n${pick(ledger.relations, 500)}',
    if (_clean(ledger.items).isNotEmpty && castNames.isNotEmpty)
      '关键物品：\n${pick(ledger.items, 300)}',
  ];
  if (blocks.isEmpty) return '';
  final text = blocks.join('\n\n');
  if (text.length <= limit) return text;
  return text.substring(0, limit);
}

/// 正文创作提示词。
String buildChapterWritePrompt({
  required String workTitle,
  required int chapterNo,
  required String chapterTitle,
  required String chapterSummary,
  String ledgerBlock = '',
  String previousTail = '',
  bool refsWork = true,
  bool refsSummary = true,
  bool refsPrev = false,
  String instruction = '',
}) {
  final title = _clean(workTitle).isEmpty ? '本作品' : _clean(workTitle);
  final chapter = _clean(chapterTitle).isEmpty
      ? '第 $chapterNo 章'
      : '第 $chapterNo 章《${_clean(chapterTitle)}》';
  final head = '请写《$title》$chapter的正文，只写这一章：以动作和对白推进，'
      '开头直接进入场景，结尾留一个具体钩子，不超过 1500 字。';
  final requirement = _clean(instruction).isEmpty
      ? '依据已选资料，写完整的一章。'
      : _clean(instruction);
  return [
    head,
    if (refsWork && ledgerBlock.isNotEmpty) '【作品资料（已定事实，不得冲突）】\n$ledgerBlock',
    if (refsSummary && _clean(chapterSummary).isNotEmpty)
      '【本章概要】\n${_clean(chapterSummary)}',
    if (refsPrev && _clean(previousTail).isNotEmpty)
      '【上一章末尾（承接语气与处境，勿重复）】\n${chapterTail(previousTail)}',
    '【作者要求】\n$requirement',
  ].filterNotEmpty().join('\n\n');
}

/// 分镜脚本（`storyboard` 接口只有 script 必填）：把参考资料拼成可直接送模型的剧本。
String buildChapterStoryboardScript({
  required String workTitle,
  required int chapterNo,
  required String chapterTitle,
  required String chapterSummary,
  String ledgerBlock = '',
  String previousTail = '',
  String currentContent = '',
  bool refsWork = true,
  bool refsSummary = true,
  bool refsPrev = false,
  String instruction = '',
}) {
  final title = _clean(workTitle).isEmpty ? '本作品' : _clean(workTitle);
  final chapter = _clean(chapterTitle).isEmpty
      ? '第 $chapterNo 章'
      : _clean(chapterTitle);
  final body = _clean(currentContent).isNotEmpty
      ? _clean(currentContent)
      : _clean(chapterSummary);
  return [
    '本章为《$title》第 $chapterNo 章《$chapter》。请拆成分镜。',
    if (refsWork && ledgerBlock.isNotEmpty) '【作品资料】\n$ledgerBlock',
    if (refsSummary && _clean(chapterSummary).isNotEmpty)
      '【本章概要】\n${_clean(chapterSummary)}',
    if (refsPrev && _clean(previousTail).isNotEmpty)
      '【上一章末尾】\n${chapterTail(previousTail)}',
    if (body.isNotEmpty) '【本章文本】\n$body',
    _clean(instruction).isEmpty
        ? '【分镜要求】逐镜换行，标注景别与运镜。'
        : '【分镜要求】\n${_clean(instruction)}',
  ].filterNotEmpty().join('\n\n');
}

/// 正文插入：保留已有内容，空行分隔追加（不覆盖作者已写的内容）。
String appendChapterText(String existing, String addition) {
  final current = existing.trimRight();
  final text = addition.trim();
  if (text.isEmpty) return existing;
  if (current.isEmpty) return text;
  return '$current\n\n$text';
}

/// 分镜追加：保留已有镜号，AI 结果按已有最大镜号续号。
///
/// 返回新内容与新增镜头数；没有可解析的镜头行时原样返回（[added] 为 0）。
({String content, int added}) appendStoryboardShots(
  String existing,
  String incoming,
) {
  final current = existing.trim();
  var maxNo = 0;
  for (final line in current.split('\n')) {
    final match = RegExp(r'^\s*(\d{1,4})').firstMatch(line);
    final value = int.tryParse(match?.group(1) ?? '') ?? 0;
    if (value > maxNo) maxNo = value;
  }
  final rows = incoming
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.replaceFirst(RegExp(r'^\d{1,4}\s*[.、:：|｜]?\s*'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (rows.isEmpty) return (content: current, added: 0);
  final numbered = <String>[];
  for (var index = 0; index < rows.length; index++) {
    final no = (maxNo + index + 1).toString().padLeft(2, '0');
    numbered.add('$no ${rows[index]}');
  }
  final merged = [current, numbered.join('\n')].where((v) => v.isNotEmpty).join('\n');
  return (content: merged, added: numbered.length);
}

extension _FilterNotEmpty on List<String> {
  List<String> filterNotEmpty() =>
      where((value) => value.trim().isNotEmpty).toList();
}
