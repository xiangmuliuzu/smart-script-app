import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/bookstore/data/content_providers.dart';
import 'package:script_app/features/bookstore/pages/work_storyboard_page.dart';

void main() {
  testWidgets('可试读分镜进入独立阅读页，未开放分镜留在目录', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workStoryboardsProvider(1).overrideWith((ref) async => [
              {
                'storyboardId': 10,
                'chapterTitle': '第一集分镜',
                'readable': true,
                'trialEnabled': true,
                'content': '镜头一：火车进站',
              },
              {
                'storyboardId': 11,
                'chapterTitle': '第二集分镜',
                'readable': false,
                'content': '不应展示的正文',
              },
            ]),
      ],
      child: const MaterialApp(home: WorkStoryboardPage(workId: 1)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('镜头一：火车进站'), findsNothing);
    await tester.tap(find.text('第二集分镜'));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂未开放试读'), findsOneWidget);
    expect(find.byType(StoryboardReadPage), findsNothing);
    expect(find.text('不应展示的正文'), findsNothing);
    await tester.tap(find.text('第一集分镜'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryboardReadPage), findsOneWidget);
    expect(find.text('分镜阅读'), findsOneWidget);
    expect(find.text('镜头一：火车进站'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分镜目录'), findsOneWidget);
    expect(find.text('镜头一：火车进站'), findsNothing);
  });
}
