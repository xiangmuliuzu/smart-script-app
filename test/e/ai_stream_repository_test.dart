import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/ai/data/ai_repository.dart';
import 'package:script_app/features/ai/data/ai_providers.dart';
import 'package:script_app/features/ai/ai_outline_page.dart';
import 'package:script_app/features/ai/ai_write_page.dart';
import 'package:script_app/features/ai/ai_polish_page.dart';
import 'package:script_app/features/ai/widgets/ai_inline_panel.dart';

class _StreamApi extends ApiClient {
  _StreamApi(this.stream) : super(Dio());
  final Stream<Uint8List> stream;
  @override
  Future<ResponseBody> postStream(String path,
          {dynamic data, Duration? receiveTimeout}) async =>
      ResponseBody(stream, 200);
}

void main() {
  for (final entry in <(Widget, String)>[
    (const AiOutlinePage(), '生成剧本大纲'),
    (const AiWritePage(), '生成内容'),
    (const AiPolishPage(), '开始润色'),
    (
      Scaffold(
          body: SingleChildScrollView(child: AiInlinePanel(onInsert: (_) {}))),
      '生成'
    ),
  ]) {
    testWidgets(
        '${entry.$1.runtimeType} shows the first chunk while generation is pending',
        (tester) async {
      // 加大视口：输入卡加导演选择后更高，流式结果卡需在视口内可见
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final source = StreamController<Uint8List>();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          aiRepositoryProvider
              .overrideWithValue(AiRepository(_StreamApi(source.stream))),
          // 导演(skill) 列表在测试环境走真实 HTTP 会污染流式时序，这里固定为空
          aiSkillsProvider.overrideWith((ref) async => const <AiSkill>[]),
        ],
        child: MaterialApp(home: entry.$1),
      ));
      await tester.enterText(find.byType(TextField).first, '故事要求');
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$2));
      await tester.pump();
      source.add(Uint8List.fromList(utf8.encode('data:{"delta":"书名：雨夜"}\n\n')));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('书名：雨夜'), findsOneWidget);
      source.add(Uint8List.fromList(utf8.encode(
          'data:{"delta":"的故事"}\n\ndata:{"done":true,"recordId":7,"quotaUsed":1}\n\n')));
      await tester.runAsync(() async {
        await source.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('书名：雨夜的故事'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  testWidgets('an interrupted generation keeps partial text and stops loading',
      (tester) async {
    final source = StreamController<Uint8List>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiRepositoryProvider
            .overrideWithValue(AiRepository(_StreamApi(source.stream))),
        aiSkillsProvider.overrideWith((ref) async => const <AiSkill>[]),
      ],
      child: const MaterialApp(home: AiWritePage()),
    ));
    await tester.enterText(find.byType(TextField).first, '故事要求');
    await tester.tap(find.text('生成内容'));
    await tester.pump();
    source.add(Uint8List.fromList(utf8.encode('data:{"delta":"保留下来的正文"}\n\n')));
    await source.close();
    await tester.pumpAndSettle();
    expect(find.text('保留下来的正文'), findsOneWidget);
    expect(find.text('生成已中断，已保留内容'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final type in ['write', 'polish', 'outline']) {
    test(
        '$type delivers message deltas before done and preserves completion metadata',
        () async {
      final source = StreamController<Uint8List>();
      final repo = AiRepository(_StreamApi(source.stream));
      final deltas = <String>[];
      final first = Completer<void>();
      void onDelta(String text) {
        deltas.add(text);
        if (!first.isCompleted) first.complete();
      }

      final Future<dynamic> result = switch (type) {
        'write' => repo.writeStream(prompt: '故事', onDelta: onDelta),
        'polish' => repo.polishStream(content: '原文', onDelta: onDelta),
        _ => repo.outlineStream(inspiration: '灵感', onDelta: onDelta),
      };
      source.add(Uint8List.fromList(
          utf8.encode('event:message\r\ndata:{"delta":"第一段"}\r\n\r\n')));
      try {
        await first.future.timeout(const Duration(seconds: 1));
        expect(deltas, ['第一段']);
        source.add(Uint8List.fromList(utf8.encode(
            'data:{"delta":"第二段"}\n\ndata:{"done":true,"recordId":7,"quotaUsed":1,"requestNo":"AIR-test"}\n\n')));
        final output = await result.timeout(const Duration(seconds: 1));
        if (type == 'outline') {
          expect(output.outlineText, '第一段第二段');
          expect(output.quotaUsed, 1);
          expect(output.requestNo, 'AIR-test');
        } else {
          expect(output.content, '第一段第二段');
          expect(output.recordId, 7);
        }
      } finally {
        await source.close();
      }
    });
  }

  test('a stream ending without done fails while keeping received deltas',
      () async {
    final bytes = Uint8List.fromList(utf8.encode('data:{"delta":"尚未完成"}\n\n'));
    final repo = AiRepository(_StreamApi(Stream.value(bytes)));
    final deltas = <String>[];
    await expectLater(
        repo.writeStream(prompt: '故事', onDelta: deltas.add),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('中断'))));
    expect(deltas, ['尚未完成']);
  });
}
