import 'package:shared_preferences/shared_preferences.dart';

/// 剧本大纲里的单集事件卡。
class ScriptOutlineEpisode {
  const ScriptOutlineEpisode({
    required this.no,
    required this.title,
    required this.body,
  });

  /// 集号（从 1 起）。
  final int no;

  /// 事件名（如「直播撞破」）。
  final String title;

  /// 本集事件卡全文（本集事件 / 冲突与推进 / 结果或反转 / 结尾钩子）。
  final String body;

  String get label => '第$no集：$title';
}

/// 标题行：第N集：事件名（也兼容「第N章」）——必须独占一行。
final RegExp _episodeHead = RegExp(r'^第(\d{1,3})[集章][：:]\s*(.+)$');

/// 从 AI 输出的分集事件卡文本里解析出每集标题与正文。
///
/// 只认「第N集：标题」独占一行的写法：标题行到下一个标题行之间的内容为本集正文；
/// 正文为空的集直接跳过（避免标题粘连、残块进入后续按集生成）。
List<ScriptOutlineEpisode> parseScriptOutline(String text) {
  final episodes = <ScriptOutlineEpisode>[];
  int? currentNo;
  var currentTitle = '';
  final buffer = StringBuffer();

  void flush() {
    final no = currentNo;
    final body = buffer.toString().trim();
    if (no != null && currentTitle.isNotEmpty && body.isNotEmpty) {
      episodes.add(ScriptOutlineEpisode(
        no: no,
        title: currentTitle,
        body: body,
      ));
    }
    buffer.clear();
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final match = _episodeHead.firstMatch(line);
    if (match != null) {
      flush();
      currentNo = int.tryParse(match.group(1) ?? '');
      currentTitle = (match.group(2) ?? '').trim();
      continue;
    }
    if (currentNo != null) {
      buffer.write(line);
      buffer.write('\n');
    }
  }
  flush();
  return episodes;
}

/// 作品级剧本大纲的本机存储键（与 PC 用户端 `:outline:` 同构，互不影响）。
String _outlineKey(int workId) => 'ai.scriptOutline.$workId';

/// 读取本机保存的剧本大纲；没有时返回空串。
Future<String> loadScriptOutline(int workId) async {
  if (workId <= 0) return '';
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_outlineKey(workId)) ?? '';
}

/// 保存剧本大纲到本机（传空串等于清空）。
Future<void> saveScriptOutline(int workId, String text) async {
  if (workId <= 0) return;
  final prefs = await SharedPreferences.getInstance();
  final value = text.trim();
  if (value.isEmpty) {
    await prefs.remove(_outlineKey(workId));
  } else {
    await prefs.setString(_outlineKey(workId), value);
  }
}
