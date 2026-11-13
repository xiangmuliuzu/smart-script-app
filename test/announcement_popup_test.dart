import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/message/data/announcement_entry_checker.dart';
import 'package:script_app/features/message/widgets/announcement_popup_dialog.dart';
import 'package:script_app/features/user_center/data/user_center_models.dart';
import 'package:script_app/features/user_center/data/user_center_providers.dart';

import 'support/scripted_api.dart';

void main() {
  test('公告分页解析 noticeId、标题与已读状态', () async {
    final api = ScriptedApi();
    api.reply(
        '/announcements',
        Envelope.ok({
          'total': 2,
          'list': [
            {
              'noticeId': 12,
              'noticeTitle': '平台升级',
              'noticeType': '2',
              'isRead': false,
              'createTime': '2026-11-12 10:00:00',
            },
            {
              'noticeId': 11,
              'noticeTitle': '旧公告',
              'noticeType': '1',
              'isRead': true,
              'createTime': '2026-11-01 10:00:00',
            },
          ],
        }));
    final container = ProviderContainer(overrides: [api.override]);
    addTearDown(container.dispose);

    final page =
        await container.read(messageRepositoryProvider).announcements();

    expect(page.total, 2);
    expect(page.list.first.messageId, 12);
    expect(page.list.first.title, '平台升级');
    expect(page.list.first.source, 'ANNOUNCEMENT');
    expect(page.list.first.read, false);
    expect(page.list.last.read, true);
    expect(api.countOf('/announcements'), 1);
    expect(api.requests.single.queryParameters['pageSize'], 10);
  });

  testWidgets('公告弹窗展示标题正文，点击知道了可关闭', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AnnouncementPopupDialog(
                  title: '平台升级通知',
                  content: '今晚 22:00 维护',
                ),
              ),
              child: const Text('打开公告'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开公告'));
    await tester.pumpAndSettle();
    expect(find.text('平台公告'), findsOneWidget);
    expect(find.text('平台升级通知'), findsOneWidget);
    expect(find.text('今晚 22:00 维护'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('announcement-popup')), findsNothing);
  });

  test('进入时弹最新未读公告，关闭后标记已读且公告仍可回看', () async {
    final api = ScriptedApi();
    api.reply(
        '/announcements',
        Envelope.ok({
          'total': 2,
          'list': [
            {'noticeId': 12, 'noticeTitle': '平台升级', 'isRead': false},
            {'noticeId': 11, 'noticeTitle': '旧公告', 'isRead': true},
          ],
        }));
    api.reply(
        '/announcements/12',
        Envelope.ok({
          'noticeId': 12,
          'noticeTitle': '平台升级',
          'noticeContent': '维护正文',
          'isRead': false,
        }));
    api.reply('/announcements/12/read', Envelope.ok({'changed': true}));
    final container = ProviderContainer(overrides: [api.override]);
    addTearDown(container.dispose);
    final checker = container.read(announcementEntryCheckerProvider);

    final shown = <MessageItem>[];
    final result = await checker.check(
      isSessionActive: () => true,
      present: (detail) async => shown.add(detail),
    );

    expect(result, true);
    expect(shown.single.messageId, 12);
    expect(shown.single.title, '平台升级');
    expect(shown.single.content, '维护正文');
    expect(api.countOf('/announcements/12/read'), 1);
  });

  test('没有未读公告时不弹窗，也不请求详情', () async {
    final api = ScriptedApi();
    api.reply(
        '/announcements',
        Envelope.ok({
          'total': 1,
          'list': [
            {'noticeId': 11, 'noticeTitle': '旧公告', 'isRead': true},
          ],
        }));
    final container = ProviderContainer(overrides: [api.override]);
    addTearDown(container.dispose);
    final checker = container.read(announcementEntryCheckerProvider);

    var presented = false;
    final result = await checker.check(
      isSessionActive: () => true,
      present: (_) async => presented = true,
    );

    expect(result, false);
    expect(presented, false);
    expect(api.countOf('/announcements/11'), 0);
    expect(api.countOf('/announcements/11/read'), 0);
  });
}
