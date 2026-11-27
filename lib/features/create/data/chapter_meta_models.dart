/// 本章资料（ChapterMeta）模型。
///
/// 与后端 `ChapterDraftService` 契约一一对应：
///   GET  /content/works/{workId}/chapter-meta        → { "1": {cast,items,edges,aiSummary,source,generatedAt}, ... }
///   PUT  /content/works/{workId}/chapter-meta/{no}   → 同结构（单章）
///   POST /content/ai/chapter-meta                    → 同结构（AI 整理并落库）
///   POST /content/ai/chapter-draft/stream            → SSE done 携带 {draft:{title,summary,cast,items,edges,...}}
///
/// cast / items 的条目只引用作品级人物/物品 key，名称以作品资料为准，避免双写漂移；
/// edges 两端必须是本章 cast 中的人物 key。
library;

import 'blueprint_models.dart';

String _text(dynamic value) => value == null ? '' : value.toString();

/// 本章出场人物 / 物品条目。
class ChapterMetaEntry {
  const ChapterMetaEntry({
    this.key = '',
    this.name = '',
    this.role = '',
    this.change = '',
  });

  /// 作品级人物 / 物品 key（后端保证非空）。
  final String key;
  final String name;

  /// 本章身份 / 本章用途。
  final String role;

  /// 本章变化。
  final String change;

  factory ChapterMetaEntry.fromJson(Map<String, dynamic> json) =>
      ChapterMetaEntry(
        key: cleanBlueprintText(json['key']),
        name: cleanBlueprintText(json['name']),
        role: cleanBlueprintText(json['role']),
        change: cleanBlueprintText(json['change']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'name': name,
        'role': role,
        'change': change,
      };
}

/// 本章关系边（a/b 为人物 key）。
class ChapterMetaEdge {
  const ChapterMetaEdge({
    this.a = '',
    this.b = '',
    this.label = '',
    this.dash = false,
  });

  final String a;
  final String b;
  final String label;
  final bool dash;

  factory ChapterMetaEdge.fromJson(Map<String, dynamic> json) =>
      ChapterMetaEdge(
        a: cleanBlueprintText(json['a']),
        b: cleanBlueprintText(json['b']),
        label: cleanBlueprintText(json['label']),
        dash: json['dash'] == true,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'a': a,
        'b': b,
        'label': label,
        'dash': dash,
      };
}

/// 单章本章资料。
class ChapterMeta {
  const ChapterMeta({
    this.cast = const [],
    this.items = const [],
    this.edges = const [],
    this.aiSummary = '',
    this.source = 'manual',
    this.generatedAt = '',
  });

  static const ChapterMeta empty = ChapterMeta();

  final List<ChapterMetaEntry> cast;
  final List<ChapterMetaEntry> items;
  final List<ChapterMetaEdge> edges;

  /// AI 起草本章概要时的摘要（概要 Tab 的「AI 已起草」提示取它）。
  final String aiSummary;

  /// ai / manual。
  final String source;
  final String generatedAt;

  bool get isEmpty => cast.isEmpty && items.isEmpty && edges.isEmpty;

  /// 是否由 AI 整理（概要 Tab 首次进入提示需要）。
  bool get isAiDrafted => source == 'ai' || aiSummary.isNotEmpty;

  /// 关系图节点：出现在 edges 两端的人物 key（按 cast 顺序）。
  List<String> get relationKeys {
    final keys = <String>{};
    for (final edge in edges) {
      keys
        ..add(edge.a)
        ..add(edge.b);
    }
    return [
      for (final entry in cast)
        if (keys.contains(entry.key)) entry.key,
    ];
  }

  factory ChapterMeta.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    final rawCast = source['cast'];
    final rawItems = source['items'];
    final rawEdges = source['edges'];
    return ChapterMeta(
      cast: rawCast is List
          ? rawCast
              .whereType<Map>()
              .map((e) => ChapterMetaEntry.fromJson(Map<String, dynamic>.from(e)))
              .where((entry) => entry.key.isNotEmpty)
              .toList()
          : const [],
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => ChapterMetaEntry.fromJson(Map<String, dynamic>.from(e)))
              .where((entry) => entry.key.isNotEmpty)
              .toList()
          : const [],
      edges: rawEdges is List
          ? rawEdges
              .whereType<Map>()
              .map((e) => ChapterMetaEdge.fromJson(Map<String, dynamic>.from(e)))
              .where((edge) =>
                  edge.a.isNotEmpty && edge.b.isNotEmpty && edge.a != edge.b)
              .toList()
          : const [],
      aiSummary: cleanBlueprintText(source['aiSummary']),
      source: _text(source['source']) == 'ai' ? 'ai' : 'manual',
      generatedAt: cleanBlueprintText(source['generatedAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cast': cast.map((entry) => entry.toJson()).toList(),
        'items': items.map((entry) => entry.toJson()).toList(),
        'edges': edges.map((edge) => edge.toJson()).toList(),
        'aiSummary': aiSummary,
        'source': source,
        if (generatedAt.isNotEmpty) 'generatedAt': generatedAt,
      };
}

/// 本章资料整表：`{章号: 本章资料}`。
class ChapterMetaTable {
  const ChapterMetaTable(this.byChapter);

  static const ChapterMetaTable empty = ChapterMetaTable(<int, ChapterMeta>{});

  final Map<int, ChapterMeta> byChapter;

  ChapterMeta of(int chapterNo) => byChapter[chapterNo] ?? ChapterMeta.empty;

  /// 某物品在各章的出场轨迹（按章号升序）。
  ///
  /// [titles] 为章节标题表（章号 → 标题），用于展示「第 N 章 · 标题」。
  List<ItemAppearance> appearancesOfItem(
    String itemKey, {
    Map<int, String> titles = const {},
  }) {
    final result = <ItemAppearance>[];
    for (final chapterNo in _sortedChapters()) {
      for (final entry in of(chapterNo).items) {
        if (entry.key != itemKey) continue;
        result.add(ItemAppearance(
          chapterNo: chapterNo,
          chapterTitle: titles[chapterNo] ?? '',
          role: entry.role,
          change: entry.change,
        ));
      }
    }
    return result;
  }

  /// 某人物在各章的出场轨迹（按章号升序）。
  List<ItemAppearance> appearancesOfCharacter(String characterKey) {
    final result = <ItemAppearance>[];
    for (final chapterNo in _sortedChapters()) {
      for (final entry in of(chapterNo).cast) {
        if (entry.key != characterKey) continue;
        result.add(ItemAppearance(
          chapterNo: chapterNo,
          role: entry.role,
          change: entry.change,
        ));
      }
    }
    return result;
  }

  List<int> _sortedChapters() => byChapter.keys.toList()..sort();

  factory ChapterMetaTable.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    final result = <int, ChapterMeta>{};
    source.forEach((key, value) {
      final chapterNo = int.tryParse(key);
      if (chapterNo == null || chapterNo < 1 || value is! Map) return;
      result[chapterNo] = ChapterMeta.fromJson(Map<String, dynamic>.from(value));
    });
    return ChapterMetaTable(result);
  }
}

/// 人物 / 物品在某章的出现记录（由本章资料汇总，只读展示）。
class ItemAppearance {
  const ItemAppearance({
    required this.chapterNo,
    this.chapterTitle = '',
    this.role = '',
    this.change = '',
  });

  final int chapterNo;
  final String chapterTitle;
  final String role;
  final String change;

  String get label => chapterNo > 0
      ? '第 $chapterNo 章${chapterTitle.isEmpty ? '' : ' · $chapterTitle'}'
      : '章节';

  String get description => change.isNotEmpty ? change : role;
}

/// `chapter-draft/stream` 的 done.draft：AI 起草的本章标题 / 概要 / 资料。
class ChapterDraftResult {
  const ChapterDraftResult({
    this.title = '',
    this.summary = '',
    this.cast = const [],
    this.items = const [],
    this.edges = const [],
    this.tokens = 0,
    this.recordId = 0,
  });

  final String title;

  /// 本章概要（≤500 字）。
  final String summary;
  final List<ChapterMetaEntry> cast;
  final List<ChapterMetaEntry> items;
  final List<ChapterMetaEdge> edges;
  final int tokens;
  final int recordId;

  bool get hasDraft => title.isNotEmpty || summary.isNotEmpty;

  ChapterMeta get meta => ChapterMeta(
        cast: cast,
        items: items,
        edges: edges,
        aiSummary: summary,
        source: 'ai',
      );

  factory ChapterDraftResult.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    final meta = ChapterMeta.fromJson(source);
    return ChapterDraftResult(
      title: cleanBlueprintText(source['title']),
      summary: cleanBlueprintText(source['summary']),
      cast: meta.cast,
      items: meta.items,
      edges: meta.edges,
      tokens: source['tokens'] is num ? (source['tokens'] as num).toInt() : 0,
      recordId:
          source['recordId'] is num ? (source['recordId'] as num).toInt() : 0,
    );
  }
}
