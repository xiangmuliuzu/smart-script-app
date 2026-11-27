// v3 作品资料：SSE 事件解析与结构化模型。
//
// 覆盖：
//   - `blueprint/stream` 的 stage / delta / done 事件（done 携带 sessionId + blueprint）；
//   - stage → 生成页 5 项进度的映射（含 items 到达时人物关系一并完成）；
//   - blueprint JSON 宽松归一（key 去重、悬空关系剔除、非法条目丢弃）；
//   - 作品资料 ↔ 台账十类双向转换（与后端 BlueprintStructure.ledger 同口径）；
//   - 台账被作者改过后合并回结构化资料；
//   - error 事件抛 ApiException（次数不足等）。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/create/data/author_work_repository.dart';
import 'package:script_app/features/create/data/blueprint_models.dart';
import 'package:script_app/features/create/data/blueprint_repository.dart';
import 'package:script_app/features/create/data/chapter_meta_models.dart';
import 'package:script_app/features/create/data/create_repository.dart';

/// 只替换 SSE 传输层的 ApiClient。
class _StreamApi extends ApiClient {
  _StreamApi(this.stream) : super(Dio());

  final Stream<Uint8List> stream;
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<ResponseBody> postStream(
    String path, {
    dynamic data,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) async {
    lastPath = path;
    lastBody = data is Map ? Map<String, dynamic>.from(data) : null;
    return ResponseBody(stream, 200);
  }
}

Stream<Uint8List> _sse(String text, {int chunkSize = 1 << 16}) async* {
  final bytes = utf8.encode(text);
  for (var index = 0; index < bytes.length; index += chunkSize) {
    final end = index + chunkSize > bytes.length ? bytes.length : index + chunkSize;
    yield Uint8List.fromList(bytes.sublist(index, end));
  }
}

BlueprintRepository _repo(ApiClient api) => BlueprintRepository(
      api,
      AuthorWorkRepository(api),
      CreateRepository(api),
    );

const _blueprintJson = {
  'status': 'draft',
  'storyCore': {
    'logline': '深夜主播听见十年前的自己。',
    'summary': '凌晨三点，城市电台只剩主播沈默一个人。',
    'coreConflict': '他越接近真相，越发现自己也在那场火里。',
    'narrativeStyle': '冷峻、克制',
    'contentBoundary': '不出现血腥画面',
    'endingTone': '克制的释然',
  },
  'world': {
    'setting': '2008 年与现在的同一座城市、同一个频率。',
    'rules': [
      {'name': '直播规则', 'detail': '只有直播中的声音能被听见。'}
    ],
    'constraints': ['每条留言只出现一次'],
  },
  'outline': {
    'mainline': '沈默追查留言来源。',
    'acts': [
      {
        'name': '第一幕',
        'range': '1-4 集',
        'summary': '发现留言',
        'beats': ['三点零七分的来源']
      }
    ],
    'endingHanger': '母带背面还有一行字',
  },
  'characters': [
    {
      'key': 'c-1',
      'name': '沈默',
      'role': '深夜电台主播',
      'age': '34',
      'gender': '男',
      'appearance': '清瘦，常穿深色针织衫。',
      'trait': '克制、念旧。',
      'goal': '找到留言的来源。',
      'growth': '从躲藏到公开真相。',
      'secret': '火灾那晚他其实在场。',
    },
    {'key': 'c-2', 'name': '林知夏', 'role': '录音师'},
  ],
  'items': [
    {
      'key': 'i-1',
      'name': '开盘母带',
      'icon': 'tape',
      'desc': '十年前的节目母带。',
      'owner': '沈默',
      'count': '1',
      'state': '被沈默从档案室带走',
    }
  ],
  'relations': [
    {'a': 'c-1', 'b': 'c-2', 'label': '旧同事 · 歉意', 'dash': false},
    {'a': 'c-1', 'b': 'c-missing', 'label': '悬空关系', 'dash': true},
  ],
  'planEpisodes': 12,
  'minutesPerEpisode': 2,
};

void main() {
  group('Blueprint SSE', () {
    test('stage / delta / done 事件推进进度并返回会话', () async {
      final stages = <String>[];
      final deltas = <String>[];
      final api = _StreamApi(_sse(
        ': connected\n\n'
        'event:stage\ndata:{"stage":"story"}\n\n'
        'event:message\ndata:{"delta":"{\\"storyCore\\":"}\n\n'
        'event:stage\ndata:{"stage":"world"}\n\n'
        'event:stage\ndata:{"stage":"characters"}\n\n'
        'event:stage\ndata:{"stage":"items"}\n\n'
        'event:stage\ndata:{"stage":"outline"}\n\n'
        'event:message\ndata:${jsonEncode({'done': true, 'sessionId': 88, 'quotaUsed': 3, 'blueprint': _blueprintJson})}\n\n',
      ));
      final session = await _repo(api).generate(
        title: '深夜频率',
        inspiration: '深夜电台主播在听众留言里听到十年前的自己。',
        genre: '都市悬疑',
        onStage: stages.add,
        onDelta: deltas.add,
      );

      expect(stages, ['story', 'world', 'characters', 'items', 'outline']);
      expect(deltas.join(), contains('storyCore'));
      expect(session.sessionId, 88);
      expect(session.blueprint.characters.length, 2);
      expect(session.blueprint.items.single.name, '开盘母带');
      // 悬空关系（c-missing）被剔除。
      expect(session.blueprint.relations.length, 1);
      // 入参口径：genre 为自由文本，service 缺省集数由后端兜底。
      expect(api.lastPath, '/content/ai/blueprint/stream');
      expect(api.lastBody?['title'], '深夜频率');
      expect(api.lastBody?['genre'], '都市悬疑');
      expect(api.lastBody?.containsKey('episodes'), isFalse);
    });

    test('error 事件抛 ApiException 并带业务码', () async {
      final api = _StreamApi(_sse(
        'event:error\ndata:{"code":400,"message":"积分不足，当前可用: 0"}\n\n',
      ));
      await expectLater(
        _repo(api).generate(title: '书名', inspiration: '故事灵感至少十个字符'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 400)
            .having((e) => e.message, 'message', contains('积分不足'))),
      );
    });

    test('没有 done 事件时提示中断且不返回会话', () async {
      final api = _StreamApi(_sse('event:message\ndata:{"delta":"半截"}\n\n'));
      await expectLater(
        _repo(api).generate(title: '书名', inspiration: '故事灵感至少十个字符'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('生成中断'))),
      );
    });

    test('重新整理按 section 下发并返回最新资料', () async {
      final api = _StreamApi(_sse(
        'event:stage\ndata:{"stage":"characters"}\n\n'
        'event:message\ndata:${jsonEncode({'done': true, 'sessionId': 88, 'blueprint': _blueprintJson})}\n\n',
      ));
      final session = await _repo(api).regenerate(
        sessionId: 88,
        section: 'characters',
        key: 'c-1',
        instruction: '更冷峻一点',
      );
      expect(api.lastPath, '/content/ai/blueprint/regenerate');
      expect(api.lastBody?['section'], 'characters');
      expect(api.lastBody?['key'], 'c-1');
      expect(api.lastBody?['instruction'], '更冷峻一点');
      expect(session.blueprint.storySummary, contains('凌晨三点'));
    });
  });

  group('生成进度映射', () {
    test('stage 依次点亮故事核心 / 世界 / 人物 / 物品与关系', () {
      var progress = BlueprintStageProgress.fromStage('story');
      expect(progress.stateOf(0), 'run');
      expect(progress.stateOf(1), 'pending');

      progress = BlueprintStageProgress.fromStage('characters');
      expect(progress.stateOf(0), 'done');
      expect(progress.stateOf(1), 'done');
      expect(progress.stateOf(2), 'run');
      expect(progress.stateOf(3), 'pending');

      // 物品与人物关系同批产出：items 到达时关键物品完成，人物关系进入整理中。
      progress = BlueprintStageProgress.fromStage('items');
      expect(progress.stateOf(3), 'done');
      expect(progress.stateOf(4), 'run');

      progress = BlueprintStageProgress.fromStage('outline');
      expect(progress.allDone, isTrue);
    });
  });

  group('作品资料模型', () {
    test('宽松归一：同名 key 去重、空字段补空', () {
      final blueprint = StoryBlueprint.fromJson({
        'characters': [
          {'key': 'c-1', 'name': '沈默'},
          {'key': 'c-1', 'name': '林知夏'},
        ],
        'items': [
          {'name': '母带'},
        ],
        'planEpisodes': 99,
        'minutesPerEpisode': 0,
      });
      expect(blueprint.characters.first.key, 'c-1');
      expect(blueprint.characters.last.key, 'c-1x');
      expect(blueprint.items.single.key, blueprintNameKey('i', '母带'));
      // 越界集数 / 非法时长回落到缺省值。
      expect(blueprint.planEpisodes, 12);
      expect(blueprint.minutesPerEpisode, 2);
    });

    test('nameKey 与后端 StructuredWritingJson 算法一致', () {
      // 后端：(hash*31+codePoint) % Integer.MAX_VALUE，36 进制输出。
      expect(blueprintNameKey('c', '沈默'), 'c-jbyo');
      expect(
        blueprintNameKey('i', 'A'),
        'i-${('A'.codeUnitAt(0)).toRadixString(36)}',
      );
    });

    test('作品资料 → 台账十类，字段口径与后端一致', () {
      final blueprint = StoryBlueprint.fromJson(Map<String, dynamic>.from(_blueprintJson));
      final ledger = blueprintToLedger(blueprint);
      expect(ledger.storySummary, contains('凌晨三点'));
      expect(ledger.characters, contains('沈默（34/男）：深夜电台主播｜'));
      expect(ledger.relations, '沈默 ↔ 林知夏：旧同事 · 歉意');
      expect(ledger.props, contains('开盘母带｜1｜沈默｜被沈默从档案室带走'));
      expect(ledger.items, '开盘母带：被沈默从档案室带走');
      expect(ledger.styleGuide, contains('冷峻、克制'));
      expect(ledger.foreshadow, '每条留言只出现一次');
      expect(ledger.outline, contains('故事主线：沈默追查留言来源。'));
      expect(ledger.outline, contains('第一幕（1-4 集）：发现留言。节拍：三点零七分的来源'));
      expect(ledger.outline, contains('结尾悬念：母带背面还有一行字'));
      expect(ledger.stateBoard, contains('计划集数=12 集；单集时长=2 分钟。'));
      expect(ledger.stateBoard, contains('核心冲突：'));
      expect(ledger.stateBoard, contains('世界观：'));
    });

    test('台账（旧作品）→ 结构化资料', () {
      const ledger = WorkLedger(
        storySummary: '沈默追查一条来自十年前的留言。',
        characters: '沈默（34/男）：主播｜清瘦｜克制｜找到来源｜说出真相｜火灾在场\n'
            '林知夏（29/女）：录音师',
        relations: '沈默 ↔ 林知夏：旧同事 · 歉意',
        props: '开盘母带｜1｜沈默｜被带走｜十年前的节目母带',
        outline: '故事主线：追查留言\n第一幕（1-4 集）：发现留言\n结尾悬念：母带背面的字',
        styleGuide: '冷峻\n不出现血腥',
        threads: '每条留言只出现一次',
        stateBoard: '计划集数=12 集；单集时长=2 分钟。\n'
            '核心冲突：他在场。\n世界观：同一座城市。\n直播规则：只有直播中的声音能被听见。\n结局基调：释然',
        updateTime: '2026-11-27 10:00:00',
      );
      final blueprint = ledgerToBlueprint(ledger);
      expect(blueprint.characters.length, 2);
      expect(blueprint.characterByName('沈默')?.secret, '火灾在场');
      expect(blueprint.relations.single.label, '旧同事 · 歉意');
      expect(blueprint.items.single.owner, '沈默');
      expect(blueprint.world.constraints, ['每条留言只出现一次']);
      expect(blueprint.world.rules.single.name, '直播规则');
      expect(blueprint.storyCore.coreConflict, '他在场。');
      expect(blueprint.outline.acts.single.summary, '发现留言');
      expect(blueprint.planEpisodes, 12);
      expect(blueprint.isConfirmed, isTrue);
    });

  });

  group('本章资料模型', () {
    test('chapter-meta 整表与单章资料解析', () {
      final table = ChapterMetaTable.fromJson({
        '1': {
          'cast': [
            {'key': 'c-1', 'name': '沈默', 'role': '主播', 'change': '接到留言'},
            {'key': '', 'name': '无效条目'},
          ],
          'items': [
            {'key': 'i-1', 'name': '开盘母带', 'role': '本章上场'},
          ],
          'edges': [
            {'a': 'c-1', 'b': 'c-2', 'label': '重新联系', 'dash': false},
          ],
          'aiSummary': '沈默接到一通来自 2008 年的留言。',
          'source': 'ai',
        },
        'x': {'cast': <Object>[]},
      });
      final meta = table.of(1);
      expect(meta.cast.length, 1);
      expect(meta.items.single.name, '开盘母带');
      expect(meta.relationKeys, ['c-1']);
      expect(meta.isAiDrafted, isTrue);
      expect(table.of(2).isEmpty, isTrue);
      expect(table.byChapter.containsKey(0), isFalse);
    });

    test('chapter-draft done.draft 解析为标题 / 概要 / 本章资料', () {
      final draft = ChapterDraftResult.fromJson({
        'title': '无人接听',
        'summary': '凌晨三点，沈默照常开播。',
        'cast': [
          {'key': 'c-1', 'name': '沈默', 'role': '主播', 'change': '接到留言'},
        ],
        'items': <Object>[],
        'edges': <Object>[],
        'tokens': 1200,
        'recordId': 9,
      });
      expect(draft.hasDraft, isTrue);
      expect(draft.title, '无人接听');
      expect(draft.meta.cast.single.key, 'c-1');
      expect(draft.meta.aiSummary, '凌晨三点，沈默照常开播。');
      expect(draft.tokens, 1200);
    });
  });
}
