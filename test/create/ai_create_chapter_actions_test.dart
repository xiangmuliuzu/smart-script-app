import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/theme/app_theme.dart';
import 'package:script_app/features/create/ai_create_page.dart';
import 'package:script_app/features/create/data/ai_create_session.dart';

/// AI 创作页流程回归：
/// - 章节页主按钮必须完整落在屏幕内（主题按钮最小宽度无穷大，放进无界 Row 会被裁掉）；
/// - 顶部步骤条可切换，返回大纲不丢内容；
/// - 设定页已有大纲时是「下一步」并可「重置」。
void main() {
  Future<void> pumpChapterStep(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AiCreatePage(
            draft: AiCreateDraft(
              title: '深夜频率',
              idea: '深夜电台主播',
              episodes: 1,
              outline: '第1集：死后三小时\n本集事件：主角醒来。',
              chapters: [
                AiCreateDraftChapter(title: '第1集：死后三小时', content: '正文'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('章节页主按钮完整落在屏幕内', (tester) async {
    await pumpChapterStep(tester);

    const width = 1080 / 2.625;
    final button = find.text('进入作品工作台');
    await tester.ensureVisible(button);
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width));
    expect(rect.width, greaterThan(0));
  });

  testWidgets('点击步骤条可返回大纲且大纲不丢失', (tester) async {
    await pumpChapterStep(tester);

    await tester.tap(find.text('2 大纲'));
    await tester.pumpAndSettle();

    expect(find.text('确认大纲，进入章节生成'), findsOneWidget);
    expect(find.textContaining('第1集：死后三小时'), findsWidgets);
  });

  testWidgets('设定页已有大纲时显示下一步与重置', (tester) async {
    await pumpChapterStep(tester);

    await tester.tap(find.text('1 设定'));
    await tester.pumpAndSettle();

    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('重置'), findsOneWidget);
  });

  testWidgets('点查看正文进入独立阅读页', (tester) async {
    await pumpChapterStep(tester);

    await tester.tap(find.textContaining('查看正文'));
    await tester.pumpAndSettle();

    expect(find.text('章节正文'), findsOneWidget);
    expect(find.text('正文'), findsOneWidget);
  });
}
