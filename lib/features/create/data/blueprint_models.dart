/// v3 作品资料（AI Story Blueprint）模型与纯函数层。
///
/// 与后端 `BlueprintService` / `BlueprintStructure` 的契约一一对应：
///   GET  /content/ai/blueprint/{sessionId}          → {sessionId,status,title,workId?,updatedAt,blueprint}
///   POST /content/ai/blueprint/stream              → SSE，done 携带 {sessionId,blueprint}
///   POST /content/ai/blueprint/regenerate          → SSE，done 携带 {sessionId,blueprint}
///   GET  /content/works/{workId}/blueprint         → 同上（作品暂无会话时为 null）
///
/// blueprint 结构（后端 normalize 后）：
///   storyCore {logline, summary, coreConflict, narrativeStyle, contentBoundary, endingTone}
///   world     {setting, rules:[{name,detail}], constraints:[文字]}
///   outline   {mainline, acts:[{name,range,summary,beats}], endingHanger}
///   characters[{key,name,role,age,gender,appearance,trait,goal,growth,secret}]
///   items     [{key,name,icon,desc,owner,count,state}]
///   relations [{a,b,label,dash}]
///   planEpisodes / minutesPerEpisode / status / updatedAt
///
/// 后端没有「作品资料写接口」：作者手动修改真实落库到创作台账
/// （`PUT /content/works/{workId}/ledger`，与 PC 创作者端共用同一份）。
/// 因此本文件提供两件事：
///   1. [StoryBlueprint] ↔ 台账十类自由文本的双向转换（与后端 BlueprintStructure.ledger 对齐）；
///   2. 没有资料会话的旧作品按台账宽松还原（[ledgerToBlueprint]）。
/// 解析一律宽松降级，不抛错、不编造字段。
library;

import 'dart:convert';

String _text(dynamic value) => value == null ? '' : value.toString();

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// 统一换行并去掉首尾空白（不折叠正文内部空行）。
String cleanBlueprintText(dynamic value) =>
    _text(value).replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

/// 稳定 key：同名永远得到同一个 key，与后端 `StructuredWritingJson.nameKey` 完全一致。
String blueprintNameKey(String prefix, String name) {
  var hash = 0;
  for (final codePoint in name.runes) {
    hash = (hash * 31 + codePoint) % 0x7fffffff;
  }
  return '$prefix-${hash.toRadixString(36)}';
}

/// 取第一句（中英文句末标点或换行），用于一句话简介兜底。
String firstSentence(String value, {int limit = 120}) {
  final text = cleanBlueprintText(value).replaceAll(RegExp(r'\n+'), ' ');
  if (text.isEmpty) return '';
  final match = RegExp(r'^.*?[。！？!?；;]').firstMatch(text);
  final sentence = (match?.group(0) ?? text).trim();
  return sentence.length > limit ? sentence.substring(0, limit) : sentence;
}

/// 物品图形意图：按名称/描述猜测线稿类型（与 PC v3 `guessIcon` 同口径）。
String guessItemIcon(String name, [String desc = '']) {
  final source = '$name $desc';
  const hints = <({String icon, String pattern})>[
    (icon: 'tape', pattern: r'磁带|录音带|卡带|母带|tape'),
    (icon: 'radio', pattern: r'收音机|电台|radio|频段|频率'),
    (icon: 'note', pattern: r'留言|信纸|纸页|笔记|note|信|日记'),
    (icon: 'key', pattern: r'钥匙|key'),
    (icon: 'mask', pattern: r'面具|傩|mask'),
  ];
  for (final hint in hints) {
    if (RegExp(hint.pattern, caseSensitive: false).hasMatch(source)) {
      return hint.icon;
    }
  }
  return 'generic';
}

// ================================================================
// 结构化模型
// ================================================================

/// 故事核心。
class BlueprintStoryCore {
  const BlueprintStoryCore({
    this.logline = '',
    this.summary = '',
    this.coreConflict = '',
    this.narrativeStyle = '',
    this.contentBoundary = '',
    this.endingTone = '',
  });

  final String logline;
  final String summary;
  final String coreConflict;
  final String narrativeStyle;
  final String contentBoundary;
  final String endingTone;

  bool get isEmpty =>
      logline.isEmpty &&
      summary.isEmpty &&
      coreConflict.isEmpty &&
      narrativeStyle.isEmpty &&
      contentBoundary.isEmpty &&
      endingTone.isEmpty;

  BlueprintStoryCore copyWith({
    String? logline,
    String? summary,
    String? coreConflict,
    String? narrativeStyle,
    String? contentBoundary,
    String? endingTone,
  }) =>
      BlueprintStoryCore(
        logline: logline ?? this.logline,
        summary: summary ?? this.summary,
        coreConflict: coreConflict ?? this.coreConflict,
        narrativeStyle: narrativeStyle ?? this.narrativeStyle,
        contentBoundary: contentBoundary ?? this.contentBoundary,
        endingTone: endingTone ?? this.endingTone,
      );

  factory BlueprintStoryCore.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    return BlueprintStoryCore(
      logline: cleanBlueprintText(source['logline']),
      summary: cleanBlueprintText(source['summary']),
      coreConflict: cleanBlueprintText(source['coreConflict']),
      narrativeStyle: cleanBlueprintText(source['narrativeStyle']),
      contentBoundary: cleanBlueprintText(source['contentBoundary']),
      endingTone: cleanBlueprintText(source['endingTone']),
    );
  }
}

/// 世界规则条目。
class BlueprintWorldRule {
  const BlueprintWorldRule({this.name = '', this.detail = ''});

  final String name;
  final String detail;

  bool get isEmpty => name.isEmpty && detail.isEmpty;

  factory BlueprintWorldRule.fromJson(Map<String, dynamic> json) =>
      BlueprintWorldRule(
        name: cleanBlueprintText(json['name']),
        detail: cleanBlueprintText(json['detail']),
      );
}

/// 世界与规则。
class BlueprintWorld {
  const BlueprintWorld({
    this.setting = '',
    this.rules = const [],
    this.constraints = const [],
  });

  final String setting;
  final List<BlueprintWorldRule> rules;
  final List<String> constraints;

  bool get isEmpty => setting.isEmpty && rules.isEmpty && constraints.isEmpty;

  BlueprintWorld copyWith({
    String? setting,
    List<BlueprintWorldRule>? rules,
    List<String>? constraints,
  }) =>
      BlueprintWorld(
        setting: setting ?? this.setting,
        rules: rules ?? this.rules,
        constraints: constraints ?? this.constraints,
      );

  factory BlueprintWorld.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    final rawRules = source['rules'];
    final rawConstraints = source['constraints'];
    return BlueprintWorld(
      setting: cleanBlueprintText(source['setting']),
      rules: rawRules is List
          ? rawRules
              .whereType<Map>()
              .map((e) => BlueprintWorldRule.fromJson(Map<String, dynamic>.from(e)))
              .where((rule) => !rule.isEmpty)
              .toList()
          : const [],
      constraints: rawConstraints is List
          ? rawConstraints
              .map(cleanBlueprintText)
              .where((value) => value.isNotEmpty)
              .toList()
          : const [],
    );
  }
}

/// 三幕之一。
class BlueprintAct {
  const BlueprintAct({
    this.name = '',
    this.range = '',
    this.summary = '',
    this.beats = const [],
  });

  final String name;
  final String range;
  final String summary;
  final List<String> beats;

  factory BlueprintAct.fromJson(Map<String, dynamic> json) {
    final rawBeats = json['beats'];
    return BlueprintAct(
      name: cleanBlueprintText(json['name']),
      range: cleanBlueprintText(json['range']),
      summary: cleanBlueprintText(json['summary']),
      beats: rawBeats is List
          ? rawBeats
              .map(cleanBlueprintText)
              .where((value) => value.isNotEmpty)
              .toList()
          : const [],
    );
  }
}

/// 作品大纲（三幕推进，不含章节级大纲）。
class BlueprintOutline {
  const BlueprintOutline({
    this.mainline = '',
    this.acts = const [],
    this.endingHanger = '',
  });

  final String mainline;
  final List<BlueprintAct> acts;
  final String endingHanger;

  bool get isEmpty => mainline.isEmpty && acts.isEmpty && endingHanger.isEmpty;

  factory BlueprintOutline.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    final rawActs = source['acts'];
    return BlueprintOutline(
      mainline: cleanBlueprintText(source['mainline']),
      acts: rawActs is List
          ? rawActs
              .whereType<Map>()
              .map((e) => BlueprintAct.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      endingHanger: cleanBlueprintText(source['endingHanger']),
    );
  }
}

/// 主要人物。
class BlueprintCharacter {
  const BlueprintCharacter({
    this.key = '',
    this.name = '',
    this.role = '',
    this.age = '',
    this.gender = '',
    this.appearance = '',
    this.trait = '',
    this.goal = '',
    this.growth = '',
    this.secret = '',
  });

  final String key;
  final String name;
  final String role;
  final String age;
  final String gender;
  final String appearance;
  final String trait;
  final String goal;
  final String growth;
  final String secret;

  /// 身份摘要（人物卡副标题）：优先身份，其次年龄/性别。
  String get subtitle {
    final identity = [role, [age, gender].where((v) => v.isNotEmpty).join(' ')]
        .where((v) => v.isNotEmpty)
        .join(' · ');
    return identity;
  }

  /// 一句话简介：优先人物目标，其次外貌气质。
  String get brief {
    if (goal.isNotEmpty) return goal;
    if (appearance.isNotEmpty) return appearance;
    if (trait.isNotEmpty) return trait;
    return '';
  }

  Map<String, dynamic> toLedgerFields() => <String, dynamic>{
        'key': key,
        'name': name,
        'role': role,
        'age': age,
        'gender': gender,
        'appearance': appearance,
        'trait': trait,
        'goal': goal,
        'growth': growth,
        'secret': secret,
      };

  BlueprintCharacter copyWith({
    String? key,
    String? name,
    String? role,
    String? age,
    String? gender,
    String? appearance,
    String? trait,
    String? goal,
    String? growth,
    String? secret,
  }) =>
      BlueprintCharacter(
        key: key ?? this.key,
        name: name ?? this.name,
        role: role ?? this.role,
        age: age ?? this.age,
        gender: gender ?? this.gender,
        appearance: appearance ?? this.appearance,
        trait: trait ?? this.trait,
        goal: goal ?? this.goal,
        growth: growth ?? this.growth,
        secret: secret ?? this.secret,
      );

  factory BlueprintCharacter.fromJson(
    Map<String, dynamic> json, {
    int index = 0,
  }) {
    final name = cleanBlueprintText(json['name']).isEmpty
        ? '人物${index + 1}'
        : cleanBlueprintText(json['name']);
    return BlueprintCharacter(
      key: cleanBlueprintText(json['key']).isEmpty
          ? blueprintNameKey('c', name)
          : cleanBlueprintText(json['key']),
      name: name,
      role: cleanBlueprintText(json['role']),
      age: cleanBlueprintText(json['age']),
      gender: cleanBlueprintText(json['gender']),
      appearance: cleanBlueprintText(json['appearance']),
      trait: cleanBlueprintText(json['trait']),
      goal: cleanBlueprintText(json['goal']),
      growth: cleanBlueprintText(json['growth']),
      secret: cleanBlueprintText(json['secret']),
    );
  }
}

/// 关键物品（后端只存 name/icon/desc/owner/count/state，出现章节由本章资料推导）。
class BlueprintItem {
  const BlueprintItem({
    this.key = '',
    this.name = '',
    this.icon = '',
    this.desc = '',
    this.owner = '',
    this.count = '',
    this.state = '',
  });

  final String key;
  final String name;
  final String icon;
  final String desc;
  final String owner;
  final String count;
  final String state;

  String get glyphIcon => icon.isEmpty ? guessItemIcon(name, desc) : icon;

  /// 副标题：持有人 + 状态。
  String get subtitle {
    final holder = owner.isEmpty ? '' : '$owner 持有';
    return [state, holder].where((v) => v.isNotEmpty).join(' · ');
  }

  BlueprintItem copyWith({
    String? key,
    String? name,
    String? icon,
    String? desc,
    String? owner,
    String? count,
    String? state,
  }) =>
      BlueprintItem(
        key: key ?? this.key,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        desc: desc ?? this.desc,
        owner: owner ?? this.owner,
        count: count ?? this.count,
        state: state ?? this.state,
      );

  Map<String, dynamic> toLedgerFields() => <String, dynamic>{
        'key': key,
        'name': name,
        'icon': icon,
        'desc': desc,
        'owner': owner,
        'count': count,
        'state': state,
      };

  factory BlueprintItem.fromJson(Map<String, dynamic> json, {int index = 0}) {
    final name = cleanBlueprintText(json['name']).isEmpty
        ? '物品${index + 1}'
        : cleanBlueprintText(json['name']);
    final desc = cleanBlueprintText(json['desc']);
    return BlueprintItem(
      key: cleanBlueprintText(json['key']).isEmpty
          ? blueprintNameKey('i', name)
          : cleanBlueprintText(json['key']),
      name: name,
      icon: cleanBlueprintText(json['icon']),
      desc: desc,
      owner: cleanBlueprintText(json['owner']),
      count: cleanBlueprintText(json['count']),
      state: cleanBlueprintText(json['state']),
    );
  }
}

/// 人物关系边（a/b 为人物 key）。
class BlueprintRelation {
  const BlueprintRelation({
    this.a = '',
    this.b = '',
    this.label = '',
    this.dash = false,
  });

  final String a;
  final String b;
  final String label;

  /// 虚线：未公开 / 推断的关系。
  final bool dash;

  factory BlueprintRelation.fromJson(Map<String, dynamic> json) =>
      BlueprintRelation(
        a: cleanBlueprintText(json['a']),
        b: cleanBlueprintText(json['b']),
        label: cleanBlueprintText(json['label']),
        dash: json['dash'] == true,
      );
}

/// 整份作品资料。
class StoryBlueprint {
  const StoryBlueprint({
    this.status = 'draft',
    this.storyCore = const BlueprintStoryCore(),
    this.world = const BlueprintWorld(),
    this.outline = const BlueprintOutline(),
    this.characters = const [],
    this.items = const [],
    this.relations = const [],
    this.planEpisodes = 12,
    this.minutesPerEpisode = 2,
    this.updatedAt = '',
  });

  final String status;
  final BlueprintStoryCore storyCore;
  final BlueprintWorld world;
  final BlueprintOutline outline;
  final List<BlueprintCharacter> characters;
  final List<BlueprintItem> items;

  /// 关系两端一定落在 [characters] 的 key 上。
  final List<BlueprintRelation> relations;
  final int planEpisodes;
  final double minutesPerEpisode;
  final String updatedAt;

  bool get isConfirmed => status == 'confirmed';

  /// 一句话简介（故事核心 logline 缺失时用简介首句）。
  String get oneLineIntro {
    if (storyCore.logline.isNotEmpty) return storyCore.logline;
    return firstSentence(storyCore.summary);
  }

  /// 故事核心正文段落：简介优先，缺失时用一句话简介兜底。
  String get storySummary =>
      storyCore.summary.isNotEmpty ? storyCore.summary : oneLineIntro;

  BlueprintCharacter? characterByKey(String key) {
    for (final character in characters) {
      if (character.key == key) return character;
    }
    return null;
  }

  BlueprintItem? itemByKey(String key) {
    for (final item in items) {
      if (item.key == key) return item;
    }
    return null;
  }

  BlueprintCharacter? characterByName(String name) {
    final wanted = cleanBlueprintText(name);
    if (wanted.isEmpty) return null;
    for (final character in characters) {
      if (character.name == wanted) return character;
    }
    for (final character in characters) {
      if (character.name.contains(wanted) || wanted.contains(character.name)) {
        return character;
      }
    }
    return null;
  }

  StoryBlueprint copyWith({
    String? status,
    BlueprintStoryCore? storyCore,
    BlueprintWorld? world,
    BlueprintOutline? outline,
    List<BlueprintCharacter>? characters,
    List<BlueprintItem>? items,
    List<BlueprintRelation>? relations,
    int? planEpisodes,
    double? minutesPerEpisode,
    String? updatedAt,
  }) =>
      StoryBlueprint(
        status: status ?? this.status,
        storyCore: storyCore ?? this.storyCore,
        world: world ?? this.world,
        outline: outline ?? this.outline,
        characters: characters ?? this.characters,
        items: items ?? this.items,
        relations: relations ?? this.relations,
        planEpisodes: planEpisodes ?? this.planEpisodes,
        minutesPerEpisode: minutesPerEpisode ?? this.minutesPerEpisode,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// 宽松归一：缺字段补空、非法条目丢弃、key 去重、悬空关系剔除。
  factory StoryBlueprint.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    final rawCharacters = source['characters'];
    final seenCharacter = <String>{};
    final characters = <BlueprintCharacter>[];
    if (rawCharacters is List) {
      for (var index = 0; index < rawCharacters.length; index++) {
        final raw = rawCharacters[index];
        if (raw is! Map) continue;
        final character = BlueprintCharacter.fromJson(
          Map<String, dynamic>.from(raw),
          index: index,
        );
        var key = character.key;
        while (!seenCharacter.add(key)) {
          key = '${key}x';
        }
        characters.add(character.copyWith(key: key));
      }
    }
    final rawItems = source['items'];
    final seenItem = <String>{};
    final items = <BlueprintItem>[];
    if (rawItems is List) {
      for (var index = 0; index < rawItems.length; index++) {
        final raw = rawItems[index];
        if (raw is! Map) continue;
        final item = BlueprintItem.fromJson(
          Map<String, dynamic>.from(raw),
          index: index,
        );
        var key = item.key;
        while (!seenItem.add(key)) {
          key = '${key}x';
        }
        items.add(item.copyWith(key: key));
      }
    }
    final characterKeys = characters.map((c) => c.key).toSet();
    final rawRelations = source['relations'];
    final seenPairs = <String>{};
    final relations = <BlueprintRelation>[];
    if (rawRelations is List) {
      for (final raw in rawRelations) {
        if (raw is! Map) continue;
        final relation = BlueprintRelation.fromJson(Map<String, dynamic>.from(raw));
        if (relation.a.isEmpty ||
            relation.b.isEmpty ||
            relation.a == relation.b ||
            !characterKeys.contains(relation.a) ||
            !characterKeys.contains(relation.b)) {
          continue;
        }
        final pair = ([relation.a, relation.b]..sort()).join('|');
        if (!seenPairs.add(pair)) continue;
        relations.add(BlueprintRelation(
          a: relation.a,
          b: relation.b,
          label: relation.label.isEmpty ? '关系待补充' : relation.label,
          dash: relation.dash,
        ));
      }
    }
    final minutes = _double(source['minutesPerEpisode']);
    final episodes = _int(source['planEpisodes']);
    return StoryBlueprint(
      status: _text(source['status']) == 'confirmed' ? 'confirmed' : 'draft',
      storyCore: BlueprintStoryCore.fromJson(
          source['storyCore'] is Map
              ? Map<String, dynamic>.from(source['storyCore'] as Map)
              : null),
      world: BlueprintWorld.fromJson(source['world'] is Map
          ? Map<String, dynamic>.from(source['world'] as Map)
          : null),
      outline: BlueprintOutline.fromJson(source['outline'] is Map
          ? Map<String, dynamic>.from(source['outline'] as Map)
          : null),
      characters: characters,
      items: items,
      relations: relations,
      planEpisodes: episodes >= 1 && episodes <= 60 ? episodes : 12,
      minutesPerEpisode: minutes > 0 && minutes <= 60 ? minutes : 2,
      updatedAt: cleanBlueprintText(source['updatedAt']),
    );
  }
}

/// 作品资料会话（生成结果 / 详情接口）。
class BlueprintSession {
  const BlueprintSession({
    required this.sessionId,
    this.title = '',
    this.status = 'draft',
    this.workId = 0,
    this.updatedAt = '',
    required this.blueprint,
  });

  final int sessionId;
  final String title;
  final String status;

  /// 已确认会话关联的作品 ID；未确认时为 0。
  final int workId;
  final String updatedAt;
  final StoryBlueprint blueprint;

  bool get isConfirmed => status == 'confirmed';

  factory BlueprintSession.fromJson(Map<String, dynamic> json) =>
      BlueprintSession(
        sessionId: _int(json['sessionId']),
        title: cleanBlueprintText(json['title']),
        status: _text(json['status']) == 'confirmed' ? 'confirmed' : 'draft',
        workId: _int(json['workId']),
        updatedAt: cleanBlueprintText(json['updatedAt']),
        blueprint: StoryBlueprint.fromJson(json['blueprint'] is Map
            ? Map<String, dynamic>.from(json['blueprint'] as Map)
            : null),
      );
}

/// AI 使用记录里的「作品资料」记录（writeType=blueprint）。
///
/// 后端把 blueprint JSON 存在记录的 output_content 里，含 status / updatedAt / workId。
class BlueprintRecordData {
  const BlueprintRecordData({required this.blueprint, this.workId = 0});

  final StoryBlueprint blueprint;
  final int workId;

  bool get isConfirmed => blueprint.status == 'confirmed' || workId > 0;
}

/// 解析 blueprint 记录的 output 内容；无法解析时返回 null。
BlueprintRecordData? parseBlueprintRecordContent(String output) {
  final raw = output.trim();
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final json = Map<String, dynamic>.from(decoded);
    final workId = json['workId'] is num
        ? (json['workId'] as num).toInt()
        : int.tryParse('${json['workId'] ?? ''}') ?? 0;
    return BlueprintRecordData(
      blueprint: StoryBlueprint.fromJson(json),
      workId: workId,
    );
  } catch (_) {
    return null;
  }
}

// ================================================================
// 生成进度（SSE stage → 展示项）
// ================================================================

/// 生成页的 5 项进度（对齐原型：故事核心 / 世界与规则 / 主要人物 / 关键物品 / 人物关系）。
///
/// 后端 `BlueprintService.generateBoth` 依次下发 stage：
///   story → world → characters → items → outline
/// 其中 characters/items 与人物关系由同一次结构化调用产出（关系在 items 事件前已就绪），
/// 最后的 outline 是三幕大纲（v2 资料页不再展示），因此：
///   - items 到达时「关键物品」「人物关系」一起置为完成；
///   - outline 到达时全部完成。
class BlueprintStageProgress {
  const BlueprintStageProgress._(this.activeIndex, this.allDone);

  static const List<String> labels = <String>[
    '故事核心',
    '世界与规则',
    '主要人物',
    '关键物品',
    '人物关系',
  ];

  /// 当前进行中的下标；-1 表示尚未开始，5 表示全部完成。
  final int activeIndex;
  final bool allDone;

  static const BlueprintStageProgress idle =
      BlueprintStageProgress._(-1, false);

  static const BlueprintStageProgress done =
      BlueprintStageProgress._(5, true);

  /// 把后端 stage 映射到展示进度。
  static BlueprintStageProgress fromStage(String? stage) {
    switch (stage) {
      case 'story':
        return const BlueprintStageProgress._(0, false);
      case 'world':
        return const BlueprintStageProgress._(1, false);
      case 'characters':
        return const BlueprintStageProgress._(2, false);
      case 'items':
        // 物品与人物关系同批产出，items 事件到达时关系已完成。
        return const BlueprintStageProgress._(4, false);
      case 'relations':
        return const BlueprintStageProgress._(4, false);
      case 'outline':
      case 'done':
        return done;
      default:
        return idle;
    }
  }

  /// 单项状态：done / run / pending。
  String stateOf(int index) {
    if (allDone) return 'done';
    if (index < activeIndex) return 'done';
    if (index == activeIndex) return 'run';
    return 'pending';
  }
}

// ================================================================
// 作品资料 ↔ 创作台账
// ================================================================

/// 台账字段（与后端 SysWorkLedger 的文本列一致）。
class WorkLedger {
  const WorkLedger({
    this.storySummary = '',
    this.characters = '',
    this.relations = '',
    this.foreshadow = '',
    this.timeline = '',
    this.items = '',
    this.props = '',
    this.styleGuide = '',
    this.outline = '',
    this.threads = '',
    this.stateBoard = '',
    this.updateTime = '',
  });

  static const List<String> fieldKeys = <String>[
    'storySummary',
    'characters',
    'relations',
    'foreshadow',
    'timeline',
    'items',
    'props',
    'styleGuide',
    'outline',
    'threads',
    'stateBoard',
  ];

  final String storySummary;
  final String characters;
  final String relations;
  final String foreshadow;
  final String timeline;
  final String items;
  final String props;
  final String styleGuide;
  final String outline;
  final String threads;
  final String stateBoard;
  final String updateTime;

  String valueOf(String key) {
    switch (key) {
      case 'storySummary':
        return storySummary;
      case 'characters':
        return characters;
      case 'relations':
        return relations;
      case 'foreshadow':
        return foreshadow;
      case 'timeline':
        return timeline;
      case 'items':
        return items;
      case 'props':
        return props;
      case 'styleGuide':
        return styleGuide;
      case 'outline':
        return outline;
      case 'threads':
        return threads;
      case 'stateBoard':
        return stateBoard;
      default:
        return '';
    }
  }

  Map<String, String> toFields() =>
      <String, String>{for (final key in fieldKeys) key: valueOf(key)};

  factory WorkLedger.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    return WorkLedger(
      storySummary: cleanBlueprintText(source['storySummary']),
      characters: cleanBlueprintText(source['characters']),
      relations: cleanBlueprintText(source['relations']),
      foreshadow: cleanBlueprintText(source['foreshadow']),
      timeline: cleanBlueprintText(source['timeline']),
      items: cleanBlueprintText(source['items']),
      props: cleanBlueprintText(source['props']),
      styleGuide: cleanBlueprintText(source['styleGuide']),
      outline: cleanBlueprintText(source['outline']),
      threads: cleanBlueprintText(source['threads']),
      stateBoard: cleanBlueprintText(source['stateBoard']),
      updateTime: cleanBlueprintText(source['updateTime']),
    );
  }
}

String _oneLine(String value) =>
    value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

String _limit(String value, int max) =>
    value.length > max ? value.substring(0, max) : value;

/// 分钟展示口径：2 → 「2」，1.5 → 「1.5」。
String blueprintMinutesText(double minutes) => minutes == minutes.roundToDouble()
    ? minutes.toInt().toString()
    : minutes.toString();

/// 结构化资料 → 台账十类（字段口径与后端 `BlueprintStructure.ledger` 完全一致）。
///
/// 写台账后 PC 创作者端与 App 读到的是同一份自由文本；后端在确认/重生成时也会写同一格式，
/// 因此这里的输出与后端互相兼容。
WorkLedger blueprintToLedger(StoryBlueprint blueprint) {
  final story = blueprint.storyCore;
  final world = blueprint.world;
  final outline = blueprint.outline;

  final summary = story.summary.isNotEmpty
      ? _limit(story.summary, 500)
      : _limit(story.logline, 500);

  final characterLines = <String>[];
  for (final character in blueprint.characters) {
    final identity = [character.age, character.gender].join('/');
    final details = [
      character.role,
      character.appearance,
      character.trait,
      character.goal,
      character.growth,
      character.secret,
    ].map(_oneLine).join('｜');
    characterLines.add('${_oneLine(character.name)}'
        '${identity == '/' ? '' : '（$identity）'}：$details');
  }

  final byKey = <String, BlueprintCharacter>{
    for (final character in blueprint.characters) character.key: character,
  };
  final relationLines = <String>[];
  for (final relation in blueprint.relations) {
    final a = byKey[relation.a];
    final b = byKey[relation.b];
    if (a == null || b == null) continue;
    relationLines.add(
        '${_oneLine(a.name)} ↔ ${_oneLine(b.name)}：${_oneLine(relation.label)}');
  }

  final itemLines = <String>[];
  final propLines = <String>[];
  for (final item in blueprint.items) {
    final name = _oneLine(item.name);
    itemLines.add('$name：${_oneLine(item.state)}');
    propLines.add([
      name,
      _oneLine(item.count),
      _oneLine(item.owner),
      _oneLine(item.state),
      _oneLine(item.desc),
    ].join('｜'));
  }

  final styleLines = [story.narrativeStyle, story.contentBoundary]
      .where((value) => value.isNotEmpty)
      .join('\n');

  final outlineLines = <String>[];
  if (outline.mainline.isNotEmpty) {
    outlineLines.add('故事主线：${outline.mainline}');
  }
  for (var index = 0; index < outline.acts.length; index++) {
    final act = outline.acts[index];
    final fallbackName = ['第一幕', '第二幕', '第三幕'];
    final name = _oneLine(act.name).isEmpty
        ? (index < fallbackName.length ? fallbackName[index] : '')
        : _oneLine(act.name);
    final range = _oneLine(act.range);
    final description = _oneLine(act.summary);
    final beats = act.beats.map(_oneLine).where((v) => v.isNotEmpty).join('；');
    outlineLines.add(
      '$name${range.isEmpty ? '' : '（$range）'}：$description'
      '${beats.isEmpty ? '' : '${description.isEmpty ? '' : '。'}节拍：$beats'}',
    );
  }
  if (outline.endingHanger.isNotEmpty) {
    outlineLines.add('结尾悬念：${outline.endingHanger}');
  }

  final stateLines = <String>[
    '计划集数=${blueprint.planEpisodes} 集；单集时长=${blueprintMinutesText(blueprint.minutesPerEpisode)} 分钟。',
  ];
  if (story.coreConflict.isNotEmpty) {
    stateLines.add('核心冲突：${story.coreConflict}');
  }
  if (world.setting.isNotEmpty) {
    stateLines.add('世界观：${world.setting}');
  }
  for (final rule in world.rules) {
    if (rule.name.isEmpty && rule.detail.isEmpty) continue;
    stateLines.add('${_oneLine(rule.name)}：${_oneLine(rule.detail)}');
  }
  if (story.endingTone.isNotEmpty) {
    stateLines.add('结局基调：${story.endingTone}');
  }

  final constraints = world.constraints.join('\n');
  return WorkLedger(
    storySummary: summary,
    characters: characterLines.join('\n'),
    relations: relationLines.join('\n'),
    foreshadow: constraints,
    timeline: '',
    items: itemLines.join('\n'),
    props: propLines.join('\n'),
    styleGuide: styleLines,
    outline: outlineLines.join('\n'),
    threads: constraints,
    stateBoard: stateLines.join('\n'),
  );
}

const List<String> _palette = <String>[
  '#4a7c75',
  '#526a87',
  '#9b7048',
  '#7a5c78',
  '#6b7f4a',
  '#8a5a44',
];

/// 人物颜色（后端不下发颜色，按人物顺序取稳定色板，与 PC v3 一致）。
String blueprintCharacterColor(int index) =>
    _palette[index % _palette.length];

// ================================================================
// 台账文本 → 结构化资料（旧作品 / 作者改过台账时的降级还原）
// ================================================================

const Set<String> _rosterHeaders = <String>{
  '姓名',
  '身份',
  '性格',
  '动机',
  '目标',
  '状态',
  '背景',
  '当前状态',
  '主要人物',
  '人物',
  '角色',
  '人物关系',
  '人物便签',
  '人物增补',
  '新增人物',
  '故事简介',
  '人物卡',
  '本章出场',
  '本章人物',
  '重要道具档案',
  '写法基线',
  '世界观',
  '故事主线',
  '结尾悬念',
};

List<String> _lines(String value) =>
    value.replaceAll('\r\n', '\n').split('\n');

/// 解析台账「主要人物」行：`姓名（年龄/性别）：身份｜外貌｜性格｜目标｜成长线｜秘密`。
List<BlueprintCharacter> parseLedgerCharacters(String value) {
  final result = <BlueprintCharacter>[];
  final seen = <String>{};
  final matcher = RegExp(
    r'^[\s#>*·•\-]*([\p{L}][\p{L}\p{N}· ]{0,23})\s*(?:[（(]([^）)]{0,40})[）)])?\s*[：:]\s*(.*)$',
    unicode: true,
  );
  for (final raw in _lines(value)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final match = matcher.firstMatch(line);
    if (match == null) continue;
    final name = match.group(1)!.trim();
    if (name.isEmpty || _rosterHeaders.contains(name) || !seen.add(name)) {
      continue;
    }
    final identity = (match.group(2) ?? '').split(RegExp(r'[/／、,，]'));
    final fields = (match.group(3) ?? '').split(RegExp(r'[｜|]'));
    String field(int index) =>
        index < fields.length ? cleanBlueprintText(fields[index]) : '';
    result.add(BlueprintCharacter(
      key: blueprintNameKey('c', name),
      name: name,
      age: identity.isNotEmpty ? cleanBlueprintText(identity[0]) : '',
      gender: identity.length > 1 ? cleanBlueprintText(identity[1]) : '',
      role: field(0),
      appearance: field(1),
      trait: field(2),
      goal: field(3),
      growth: field(4),
      secret: field(5),
    ));
  }
  return result;
}

/// 解析台账「重要道具档案」行：`名称｜件数｜持有人｜当前状态｜外观`。
List<BlueprintItem> parseLedgerProps(String value) {
  final result = <BlueprintItem>[];
  final seen = <String>{};
  for (final raw in _lines(value)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final cells = line.split(RegExp(r'[｜|]')).map(cleanBlueprintText).toList();
    final name = cells.isEmpty ? '' : cells[0];
    if (name.isEmpty || !seen.add(name)) continue;
    String cell(int index) => index < cells.length ? cells[index] : '';
    result.add(BlueprintItem(
      key: blueprintNameKey('i', name),
      name: name,
      icon: guessItemIcon(name, cell(4)),
      count: cell(1),
      owner: cell(2),
      state: cell(3),
      desc: cell(4),
    ));
  }
  return result;
}

/// 解析台账「物品位置」行：`名称：状态`（道具档案缺失时兜底）。
List<BlueprintItem> parseLedgerItems(String value) {
  final result = <BlueprintItem>[];
  final seen = <String>{};
  for (final raw in _lines(value)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final cells = line.split(RegExp(r'[：:]'));
    if (cells.length < 2) continue;
    final name = cells.first.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    result.add(BlueprintItem(
      key: blueprintNameKey('i', name),
      name: name,
      icon: guessItemIcon(name),
      state: cells.sublist(1).join('：').trim(),
    ));
  }
  return result;
}

/// 解析台账「人物关系」行：`A ↔ B：关系性质`；两端必须能落到人物卡。
List<BlueprintRelation> parseLedgerRelations(
  String value,
  List<BlueprintCharacter> characters,
) {
  BlueprintCharacter? resolve(String name) {
    final wanted = cleanBlueprintText(name).replaceAll(
        RegExp(r'^[\s#*【\[『「]+|[】\]』」*\s]+$'), '');
    if (wanted.isEmpty) return null;
    for (final character in characters) {
      if (character.name == wanted) return character;
    }
    for (final character in characters) {
      if (wanted.contains(character.name) ||
          character.name.contains(wanted)) {
        return character;
      }
    }
    return null;
  }

  final result = <BlueprintRelation>[];
  final seen = <String>{};
  final matcher =
      RegExp(r'^(.{1,24}?)\s*(?:↔|<->|⇄|—|－|--|-|至|与|和)\s*(.{1,24}?)\s*[：:]\s*(.+)$');
  for (final raw in _lines(value)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final match = matcher.firstMatch(line);
    if (match == null) continue;
    final a = resolve(match.group(1)!);
    final b = resolve(match.group(2)!);
    final label = cleanBlueprintText(match.group(3));
    if (a == null || b == null || a.key == b.key || label.isEmpty) continue;
    final pair = ([a.key, b.key]..sort()).join('|');
    if (!seen.add(pair)) continue;
    result.add(BlueprintRelation(
      a: a.key,
      b: b.key,
      label: label,
      dash: RegExp(r'隐瞒|质疑|怀疑|暗|未公开|推断|疏远').hasMatch(label),
    ));
  }
  return result;
}

/// 状态板解析结果（只取资料页需要的字段）。
class LedgerStateBoard {
  const LedgerStateBoard({
    this.planEpisodes = 0,
    this.minutes = 0,
    this.coreConflict = '',
    this.endingTone = '',
    this.setting = '',
    this.rules = const [],
  });

  final int planEpisodes;
  final double minutes;
  final String coreConflict;
  final String endingTone;
  final String setting;
  final List<BlueprintWorldRule> rules;
}

LedgerStateBoard parseLedgerStateBoard(String value) {
  final plan = RegExp(r'计划集数\s*[=＝:：]\s*(\d{1,2})').firstMatch(value);
  final minutes = RegExp(r'单集时长\s*[=＝:：]\s*([\d.]+)').firstMatch(value);
  var coreConflict = '';
  var endingTone = '';
  var setting = '';
  final rules = <BlueprintWorldRule>[];
  for (final raw in _lines(value)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final match = RegExp(r'^([^：:]{1,20})\s*[：:]\s*(.*)$').firstMatch(line);
    if (match == null) continue;
    final label = match.group(1)!.trim();
    final detail = cleanBlueprintText(match.group(2));
    if (label == '核心冲突') {
      coreConflict = detail;
    } else if (label == '结局基调') {
      endingTone = detail;
    } else if (label == '世界观' || label == '世界与规则') {
      setting = detail;
    } else if (!RegExp(r'^(计划集数|单集时长)').hasMatch(label)) {
      if (label == '世界观' || detail.isEmpty) continue;
      rules.add(BlueprintWorldRule(name: label, detail: detail));
    }
  }
  return LedgerStateBoard(
    planEpisodes: int.tryParse(plan?.group(1) ?? '') ?? 0,
    minutes: double.tryParse(minutes?.group(1) ?? '') ?? 0,
    coreConflict: coreConflict,
    endingTone: endingTone,
    setting: setting,
    rules: rules,
  );
}

/// 台账全文 → 结构化资料（作品没有已确认资料会话时的降级还原）。
StoryBlueprint ledgerToBlueprint(WorkLedger ledger) {
  final characters = parseLedgerCharacters(ledger.characters);
  var items = parseLedgerProps(ledger.props);
  if (items.isEmpty) items = parseLedgerItems(ledger.items);
  final relations = parseLedgerRelations(ledger.relations, characters);
  final state = parseLedgerStateBoard(ledger.stateBoard);
  final summary = cleanBlueprintText(ledger.storySummary);
  final styleLines = _lines(ledger.styleGuide)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final constraints = _lines(ledger.threads.isEmpty ? ledger.foreshadow : ledger.threads)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final mainline = RegExp(r'故事主线\s*[：:]\s*(.+)')
      .firstMatch(ledger.outline)
      ?.group(1)
      ?.trim() ??
      '';
  final endingHanger = RegExp(r'结尾悬念\s*[：:]\s*(.+)')
      .firstMatch(ledger.outline)
      ?.group(1)
      ?.trim() ??
      '';
  final acts = <BlueprintAct>[];
  final actMatcher =
      RegExp(r'^#?[\s*>*]*(第\s*[一二三四五六七八九十]\s*幕)\s*(?:[（(]([^）)]*)[）)])?\s*[·：:\-—]?\s*(.*)$');
  for (final raw in _lines(ledger.outline)) {
    final match = actMatcher.firstMatch(raw.trim());
    if (match == null) continue;
    var range = cleanBlueprintText(match.group(2));
    var description = cleanBlueprintText(match.group(3));
    if (range.isEmpty && description.contains('：')) {
      final parts = description.split('：');
      range = cleanBlueprintText(parts.first);
      description = parts.sublist(1).join('：');
    }
    if (description.isEmpty) continue;
    acts.add(BlueprintAct(
      name: cleanBlueprintText(match.group(1)),
      range: range,
      summary: description,
    ));
  }

  return StoryBlueprint(
    status: 'confirmed',
    storyCore: BlueprintStoryCore(
      logline: firstSentence(summary),
      summary: summary,
      coreConflict: state.coreConflict,
      narrativeStyle: styleLines.isNotEmpty ? styleLines.first : '',
      contentBoundary: styleLines.length > 1 ? styleLines.sublist(1).join(' ') : '',
      endingTone: state.endingTone,
    ),
    world: BlueprintWorld(
      setting: state.setting,
      rules: state.rules,
      constraints: constraints,
    ),
    outline: BlueprintOutline(
      mainline: mainline.isEmpty ? firstSentence(summary) : mainline,
      acts: acts,
      endingHanger: endingHanger,
    ),
    characters: characters,
    items: items,
    relations: relations,
    planEpisodes:
        state.planEpisodes >= 1 && state.planEpisodes <= 60 ? state.planEpisodes : 12,
    minutesPerEpisode:
        state.minutes > 0 && state.minutes <= 60 ? state.minutes : 2,
    updatedAt: ledger.updateTime,
  );
}
