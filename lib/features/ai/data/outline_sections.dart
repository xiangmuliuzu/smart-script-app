import 'script_outline.dart';

/// AI 剧本续写结果的三段式：故事简介 / 人物增补（主要人物）/ 分集事件卡。
class OutlineSections {
  const OutlineSections({
    this.summary = '',
    this.characters = '',
    this.relations = '',
    this.outline = '',
  });

  final String summary;
  final String characters;
  final String relations;
  final String outline;

  bool get isEmpty =>
      summary.isEmpty &&
      characters.isEmpty &&
      relations.isEmpty &&
      outline.isEmpty;
}

/// 段名 → 落位目标。兼容「人物增补 / 新增人物 / 人物变化」等写法。
const Map<String, String> _sectionHeads = <String, String>{
  '故事简介': 'summary',
  '简介': 'summary',
  '主要人物': 'characters',
  '人物便签': 'characters',
  '人物增补': 'characters',
  '新增人物': 'characters',
  '人物变化': 'characters',
  '人物与状态变化': 'characters',
  '人物关系': 'relations',
  '分集事件卡': 'outline',
  '分集': 'outline',
  '剧本大纲': 'outline',
  '大纲': 'outline',
};

/// 把一行还原成纯段名（去 Markdown 井号、星号、书名号、尾部冒号）。
String _plainHead(String line) {
  var text = line.trim();
  text = text.replaceAll(RegExp(r'^#+\s*'), '');
  text = text.replaceAll(RegExp(r'^\*\*|\*\*$'), '');
  text = text.replaceAll(RegExp(r'^[【\[]|[】\]]$'), '');
  text = text.replaceAll(RegExp(r'[：:]\s*$'), '');
  return text.trim();
}

/// 按段名切分 AI 结果；没有段名时 outline 为空，由调用方回退到「从第一个第N集截取」。
OutlineSections splitOutlineSections(String text) {
  final buffers = <String, List<String>>{
    'summary': <String>[],
    'characters': <String>[],
    'relations': <String>[],
    'outline': <String>[],
  };
  var current = '';
  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final key = _sectionHeads[_plainHead(raw)];
    if (key != null) {
      // 模型偶尔把整段设定重写一遍再继续：同名段再次出现时用最新一份覆盖，
      // 否则「故事简介」会被拼成两版并排。
      buffers[key] = <String>[];
      current = key;
      continue;
    }
    if (current.isNotEmpty) buffers[current]!.add(raw);
  }
  String join(String key) => buffers[key]!.join('\n').trim();
  return OutlineSections(
    summary: join('summary'),
    characters: join('characters'),
    relations: join('relations'),
    outline: join('outline'),
  );
}

/// 人物块：以「姓名：」开头的一段（续行归入该人物）。
class _CharacterBlock {
  _CharacterBlock(this.key, this.body);
  final String key;
  String body;
}

final RegExp _characterHead = RegExp(
    r'^[-*·•\s]*(?:【)?([\u4e00-\u9fa5A-Za-z0-9·_]{1,20})(?:】)?'
    r'(?:[（(]([^）)]{0,30})[）)])?\s*[：:]\s*(.*)$');

List<_CharacterBlock> _characterBlocks(String text) {
  final blocks = <_CharacterBlock>[];
  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final match = _characterHead.firstMatch(line);
    if (match != null) {
      final key = (match.group(1) ?? '').trim();
      // 「顾守山（状态变化）：…」这种括注要保留，不能被当成无关键名丢掉。
      final note = (match.group(2) ?? '').trim();
      final body = (match.group(3) ?? '').trim();
      if (key.isNotEmpty &&
          !key.startsWith('第') &&
          !const <String>{'姓名', '身份', '性格', '关系', '备注'}.contains(key)) {
        blocks.add(_CharacterBlock(
            key, note.isEmpty ? body : '（$note）：$body'));
        continue;
      }
    }
    if (blocks.isNotEmpty) {
      blocks.last.body = '${blocks.last.body}\n$line'.trim();
    }
  }
  return blocks;
}

/// 人物便签增量合并：同名条目用新内容替换，新人物追加，绝不整段覆盖。
String mergeCharacterText(String existing, String incoming) {
  final next = incoming.trim();
  if (next.isEmpty) return existing;
  final map = <String, _CharacterBlock>{
    for (final block in _characterBlocks(existing)) block.key: block,
  };
  for (final block in _characterBlocks(next)) {
    final old = map[block.key];
    // 续写常给「姓名（状态变化）：…」这种短补丁；直接替换会冲掉原有外貌/说话方式等设定。
    // 只有新内容确实重写了整条（含旧文开头）才替换，否则追加到原条目。
    if (old != null &&
        block.body.length < old.body.length * 0.7 &&
        !block.body.contains(old.body.substring(0,
            old.body.length < 10 ? old.body.length : 10))) {
      old.body = '${old.body}\n${block.body}'.trim();
      continue;
    }
    map[block.key] = block;
  }
  return map.values
      .map((block) => block.body.startsWith('（')
          ? '${block.key}${block.body}'
          : '${block.key}：${block.body}')
      .join('\n');
}

/// 分集事件卡按集号合并：同号替换、新号追加、按集号排序。
String mergeScriptOutline(String existing, String incoming) {
  final next = incoming.trim();
  final map = <int, ScriptOutlineEpisode>{};
  for (final episode in parseScriptOutline(existing)) {
    map[episode.no] = episode;
  }
  for (final episode in parseScriptOutline(next)) {
    map[episode.no] = episode;
  }
  final list = map.values.toList()..sort((a, b) => a.no.compareTo(b.no));
  return list.map((episode) => '${episode.label}\n${episode.body}').join('\n\n');
}
