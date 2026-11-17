import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/message/pages/message_detail_page.dart';
import 'package:script_app/features/message/pages/message_list_page.dart';
import 'support/scripted_api.dart';

void main() {
  testWidgets('同编号的公告和通知在单一列表显示，关注动态独立分类', (tester) async {
    final api = ScriptedApi();
    api.reply(
        '/messages/unread-count',
        Envelope.ok({
          'total': 3,
          'byType': {'SYSTEM': 2, 'FOLLOW': 1}
        }));
    final rows = [
      {
        'messageId': 17,
        'source': 'ANNOUNCEMENT',
        'type': 'SYSTEM',
        'title': '服务升级公告',
        'summary': '升级内容'
      },
      {
        'messageId': 17,
        'source': 'NOTIFICATION',
        'type': 'SYSTEM',
        'title': '管理员通知',
        'summary': '通知内容'
      },
      {
        'messageId': 18,
        'source': 'NOTIFICATION',
        'type': 'FOLLOW',
        'title': '关注的创作者发布了新作品',
        'summary': '作品《新作》',
        'businessType': 'WORK',
        'businessId': '301',
      },
    ];
    api.handle('/messages', (request) {
      expect(request.queryParameters['includeAnnouncements'], true);
      final type = request.queryParameters['type'];
      final filtered =
          rows.where((row) => type == null || row['type'] == type).toList();
      return Envelope.ok({'total': filtered.length, 'list': filtered});
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [api.override],
        child: const MaterialApp(home: MessageListPage())));
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('服务升级公告'), findsOneWidget);
    expect(find.text('管理员通知'), findsOneWidget);
    expect(find.text('关注的创作者发布了新作品'), findsOneWidget);
    await tester.tap(find.text('系统 2'));
    await tester.pumpAndSettle();
    expect(find.text('服务升级公告'), findsOneWidget);
    expect(find.text('管理员通知'), findsOneWidget);
    expect(find.text('关注的创作者发布了新作品'), findsNothing);
    await tester.tap(find.text('关注 1'));
    await tester.pumpAndSettle();
    expect(find.text('关注的创作者发布了新作品'), findsOneWidget);
    expect(find.text('服务升级公告'), findsNothing);
    expect(find.text('管理员通知'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关注动态详情提供查看作品入口', (tester) async {
    final api = ScriptedApi();
    api.reply(
        '/messages/18',
        Envelope.ok({
          'messageId': 18,
          'type': 'FOLLOW',
          'title': '「作者甲」发布了新作品',
          'content': '您关注的创作者「作者甲」发布了新作品。\n· 作品：《新作》',
          'read': true,
          'businessType': 'WORK',
          'businessId': '301',
        }));
    await tester.pumpWidget(ProviderScope(
        overrides: [api.override],
        child: const MaterialApp(home: MessageDetailPage(messageId: 18))));
    await tester.pumpAndSettle();
    expect(find.text('关注'), findsOneWidget);
    expect(find.text('「作者甲」发布了新作品'), findsOneWidget);
    expect(find.text('查看作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('公告详情和已读请求按来源定位，不会操作同编号通知', (tester) async {
    final api = ScriptedApi();
    api.reply(
        '/announcements/17',
        Envelope.ok({
          'noticeId': 17,
          'noticeTitle': '服务升级公告',
          'noticeContent': '公告正文',
          'isRead': false
        }));
    api.reply('/announcements/17/read', Envelope.ok({'changed': true}));
    await tester.pumpWidget(ProviderScope(
        overrides: [api.override],
        child: const MaterialApp(
            home: MessageDetailPage(messageId: 17, source: 'ANNOUNCEMENT'))));
    await tester.pumpAndSettle();
    expect(find.text('公告正文'), findsOneWidget);
    expect(api.countOf('/announcements/17/read'), 1);
    expect(api.countOf('/messages/17'), 0);
    expect(tester.takeException(), isNull);
  });
}
