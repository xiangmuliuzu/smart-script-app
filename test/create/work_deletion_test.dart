import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/features/create/data/author_work_models.dart';
import 'package:script_app/features/create/data/author_work_providers.dart';
import 'package:script_app/features/create/widgets/work_settings_tab.dart';

import '../support/scripted_api.dart';

const _work = {'workId': 7, 'title': '联调作品', 'status': 'draft'};

Future<void> _openSettings(WidgetTester tester, ScriptedApi api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  api.reply('/content/categories', Envelope.ok([]));
  api.reply('/content/tags', Envelope.ok([]));
  await tester.pumpWidget(ProviderScope(
    overrides: [api.override],
    child: MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: WorkSettingsTab(
                        detail: AuthorWorkDetail.fromJson({'work': _work}),
                      ),
                    ),
                  )),
                  child: const Text('作品列表'),
                ),
              )),
    ),
  ));
  await tester.tap(find.text('作品列表'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('删除作品'));
  await tester.tap(find.text('删除作品'));
  await tester.pumpAndSettle();
  expect(find.text('确定删除《联调作品》吗？'), findsOneWidget);
}

Future<void> _code(WidgetTester tester) async {
  await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      '123456');
}

void main() {
  testWidgets('取消删除及未输入验证码时不发送删除请求', (tester) async {
    final api = ScriptedApi();
    await _openSettings(tester, api);
    await tester.tap(find.text('验证并删除'));
    await tester.pumpAndSettle();
    expect(find.text('请输入正确格式的短信验证码'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  testWidgets('发码失败不倒计时，可重新获取，作品不删除', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/works/7/delete-code', Envelope.fail(42901, '发送过于频繁'));
    await _openSettings(tester, api);
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();
    expect(find.text('发送过于频繁'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();
    expect(api.countOf('/delete-code'), 2);
    expect(api.requests.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  for (final entry in {
    40001: '验证码错误',
    40002: '验证码已失效，请重新获取',
    40901: '验证码已使用，请重新获取',
    409: '作品存在订单，请使用下架功能',
  }.entries) {
    testWidgets('删除被拒 ${entry.key}：保留弹窗并显示原因', (tester) async {
      final api = ScriptedApi();
      api.reply('/content/works/7', Envelope.fail(entry.key, entry.value));
      await _openSettings(tester, api);
      await _code(tester);
      await tester.tap(find.text('验证并删除'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(api.requests.singleWhere((r) => r.method == 'DELETE').data,
          {'code': '123456'});
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('向绑定手机号发码，验证成功后返回作品列表并刷新', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works', Envelope.ok([_work]));
    api.reply(
        '/content/works/7/delete-code',
        Envelope.ok({
          'sent': true,
          'phoneMasked': '139****0001',
      'cooldownSeconds': 30,
        }));
    api.reply('/content/works/7', Envelope.ok({'message': '删除成功'}));
    await _openSettings(tester, api);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkSettingsTab)),
        listen: false);
    final subscription = container.listen(myWorksProvider('all'), (_, __) {});
    addTearDown(subscription.close);
    await tester.pumpAndSettle();
    expect(api.countOf('/users/me/works'), 1);
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();
    expect(find.text('验证码已发送至 139****0001'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    final sent =
        api.requests.singleWhere((r) => r.path.endsWith('/delete-code'));
    expect(sent.method, 'POST');
    expect(sent.data, isNull);
    await _code(tester);
    api.gate();
    await tester.tap(find.text('验证并删除'));
    await tester.pump();
    expect(find.text('删除中…'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull);
    api.release();
    await tester.pumpAndSettle();
    expect(find.byType(WorkSettingsTab), findsNothing);
    expect(find.text('作品列表'), findsOneWidget);
    expect(api.countOf('/users/me/works'), 2);
    expect(api.requests.where((r) => r.method == 'DELETE').length, 1);
  });
}
