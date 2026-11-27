// 章节 summary 读写 + 首章 AI 概要提示 + 章节 AI 提示词。
//
// 覆盖：
//   - 章节更新：summary 为 null 时不下发（=不改），空串照发（=清空）；
//   - 新建章节显式 chapterNo，并把 AI 起草的概要一并落库；
//   - 「AI 已按作品资料起草」提示按「作品 + 章号」只展示一次；
//   - 章节 AI 提示词按参考范围拼装、正文追加与分镜续号。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/create/data/author_work_repository.dart';
import 'package:script_app/features/create/data/ai_summary_hint_store.dart';
import 'package:script_app/features/create/data/blueprint_models.dart';
import 'package:script_app/features/create/data/chapter_ai_prompt.dart';
import 'package:script_app/features/create/data/chapter_meta_models.dart';

import '../support/scripted_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('章节 summary 读写', () {
    Future<ScriptedApi> repo() async {
      final api = ScriptedApi();
      api.reply('/users/me/works', Envelope.ok(<Object>[]));
      api.reply('/content/works/7/chapters', Envelope.ok({'chapterId': 55}));
      api.reply('/content/chapters/55', Envelope.ok(null));
      return api;
    }

    test('编辑正文时不下发 summary（null=不改）', () async {
      final api = await repo();
      final client = ApiClient(api.buildDio());
      final works = AuthorWorkRepository(client);
      await works.updateChapter(55,
          workId: 7, chapterTitle: '第一章', content: '正文');
      final put = api.requests.singleWhere((r) => r.method == 'PUT');
      // 走 A 套章节更新：摘要的 null/空串语义完整。
      expect(put.path, contains('/users/me/works/7/chapters/55'));
      expect((put.data as Map).containsKey('summary'), isFalse);
    });

    test('显式传空串时下发 summary=""（清空）', () async {
      final api = await repo();
      final works = AuthorWorkRepository(ApiClient(api.buildDio()));
      await works.updateChapter(55, workId: 7, summary: '');
      final put = api.requests.singleWhere((r) => r.method == 'PUT');
      expect((put.data as Map)['summary'], '');
    });

    test('新建章节显式 chapterNo，并写入 AI 起草的概要', () async {
      final api = await repo();
      final works = AuthorWorkRepository(ApiClient(api.buildDio()));
      final id = await works.addChapter(
        7,
        chapterNo: 3,
        chapterTitle: '无人接听',
        summary: '凌晨三点，沈默照常开播。',
      );
      expect(id, 55);
      final post = api.requests.singleWhere((r) => r.method == 'POST');
      expect((post.data as Map)['chapterNo'], 3);
      expect((post.data as Map)['summary'], '凌晨三点，沈默照常开播。');
    });
  });

  group('首章 AI 概要提示', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('按「作品 + 章号」只提示一次', () async {
      expect(await AiSummaryHintStore.hasSeen(7, 1), isFalse);
      await AiSummaryHintStore.markSeen(7, 1);
      expect(await AiSummaryHintStore.hasSeen(7, 1), isTrue);
      // 其它章、其它作品不受影响。
      expect(await AiSummaryHintStore.hasSeen(7, 2), isFalse);
      expect(await AiSummaryHintStore.hasSeen(8, 1), isFalse);
      await AiSummaryHintStore.markSeen(7, 2);
      expect(await AiSummaryHintStore.hasSeen(7, 2), isTrue);
    });

    test('只对 AI 起草的本章资料展示', () {
      expect(const ChapterMeta().isAiDrafted, isFalse);
      expect(const ChapterMeta(source: 'manual').isAiDrafted, isFalse);
      expect(const ChapterMeta(source: 'ai').isAiDrafted, isTrue);
      // 有 AI 摘要但 source 缺失的旧数据也视为 AI 起草。
      expect(const ChapterMeta(aiSummary: '草稿').isAiDrafted, isTrue);
    });
  });

  group('章节 AI 提示词', () {
    const story = BlueprintStoryCore(
      summary: '沈默在深夜电台接到来自十年前的留言。',
      narrativeStyle: '冷峻',
    );

    WorkLedger ledger() => WorkLedger(
          storySummary: story.summary,
          characters: '沈默（34/男）：主播｜清瘦',
          relations: '沈默 ↔ 林知夏：旧同事',
          items: '开盘母带：被沈默带走',
        );

    test('参考范围决定注入哪些上下文', () {
      final full = buildChapterWritePrompt(
        workTitle: '深夜频率',
        chapterNo: 1,
        chapterTitle: '无人接听',
        chapterSummary: '凌晨三点，沈默照常开播。',
        ledgerBlock: ledgerPromptBlock(ledger(), castNames: ['沈默']),
        previousTail: '上一章末尾。',
        refsWork: true,
        refsSummary: true,
        refsPrev: true,
        instruction: '结尾更悬疑',
      );
      expect(full, contains('【作品资料（已定事实，不得冲突）】'));
      expect(full, contains('沈默（34/男）'));
      expect(full, contains('【本章概要】'));
      expect(full, contains('【上一章末尾'));
      expect(full, contains('【作者要求】\n结尾更悬疑'));

      final minimal = buildChapterWritePrompt(
        workTitle: '深夜频率',
        chapterNo: 1,
        chapterTitle: '无人接听',
        chapterSummary: '凌晨三点，沈默照常开播。',
        ledgerBlock: ledgerPromptBlock(ledger()),
        previousTail: '上一章末尾。',
        refsWork: false,
        refsSummary: false,
        refsPrev: false,
      );
      expect(minimal, isNot(contains('【作品资料')));
      expect(minimal, isNot(contains('【本章概要')));
      expect(minimal, isNot(contains('【上一章末尾')));
      expect(minimal, contains('依据已选资料，写完整的一章。'));
    });

    test('分镜脚本带本章正文与分镜要求', () {
      final script = buildChapterStoryboardScript(
        workTitle: '深夜频率',
        chapterNo: 2,
        chapterTitle: '母带',
        chapterSummary: '沈默播放母带。',
        currentContent: '母带在播放到一半时卡住。',
        instruction: '按 5 个镜头拆分',
      );
      expect(script, contains('请拆成分镜'));
      expect(script, contains('【本章文本】\n母带在播放到一半时卡住。'));
      expect(script, contains('【分镜要求】\n按 5 个镜头拆分'));
    });

    test('正文追加不覆盖已有内容；分镜按已有最大镜号续号', () {
      expect(appendChapterText('', '第一段'), '第一段');
      expect(appendChapterText('已有正文', '新的一段'), '已有正文\n\n新的一段');

      final appended = appendStoryboardShots(
        '01 特写｜红灯亮起\n02 中景｜沈默抬头',
        '03 特写｜屏幕\n04 外｜雨夜',
      );
      expect(appended.added, 2);
      expect(appended.content, contains('03 特写｜屏幕'));
      expect(appended.content, contains('04 外｜雨夜'));

      final empty = appendStoryboardShots('', '01 特写｜红灯亮起');
      expect(empty.added, 1);
      expect(empty.content, '01 特写｜红灯亮起');
      expect(appendStoryboardShots('01 特写｜红灯', '   ').added, 0);
    });
  });

  group('AI 记录里的作品资料', () {
    test('blueprint 记录可按记录内容判断确认态', () {
      const record = AiWriteRecord(
        recordId: 12,
        writeType: 'blueprint',
        title: '[起稿]《深夜频率》',
        outputContent:
            '{"status":"draft","storyCore":{"summary":"简介"},"characters":[{"key":"c-1","name":"沈默"}]}',
      );
      final parsed = parseBlueprintRecordContent(record.outputContent);
      expect(parsed, isNotNull);
      expect(parsed!.isConfirmed, isFalse);
      expect(parsed.blueprint.characters.single.name, '沈默');
      expect(parseBlueprintRecordContent('不是 JSON'), isNull);
    });
  });
}
