import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/message/pages/message_detail_page.dart';
import 'package:script_app/features/user_center/data/paged_data.dart';
import 'package:script_app/features/user_center/data/user_center_providers.dart';
import 'package:script_app/features/user_center/widgets/paged_list_controller.dart';
import 'support/scripted_api.dart';

void main() {
  test('公告解析使用公告ID及真实已读状态，与站内消息ID无关', () async {
    final api = ScriptedApi();
    api.reply('/announcements/17', Envelope.ok({
      'noticeId': 17,
      'messageId': 99,
      'noticeTitle': '测试公告',
      'noticeType': '1',
      'isRead': true,
      'noticeContent': '纯文本\n第二行'
    }));
    final container = ProviderContainer(overrides: [api.override]);
    addTearDown(container.dispose);
    final notice = await container.read(messageRepositoryProvider)
        .detail(17, source: 'ANNOUNCEMENT');
    expect(notice.messageId, 17);
    expect(notice.source, 'ANNOUNCEMENT');
    expect(notice.read, true);
    expect(notice.type, 'SYSTEM');
    expect(notice.content, '纯文本\n第二行');
  });

  testWidgets('统一消息页标记公告已读失败时仍保留正文', (tester) async {
    final api = ScriptedApi();
    api.reply('/announcements/17', Envelope.ok({
      'noticeId': 17,
      'noticeTitle': '平台服务升级',
      'noticeContent': '服务升级公告正文',
      'isRead': false,
    }));
    api.reply('/announcements/17/read', Envelope.http(503, '网络异常'));
    await tester.pumpWidget(ProviderScope(
        overrides: [api.override],
        child: const MaterialApp(home: MessageDetailPage(
          messageId: 17, source: 'ANNOUNCEMENT'))));
    await tester.pumpAndSettle();
    expect(find.text('服务升级公告正文'), findsOneWidget);
    expect(api.countOf('/announcements/17/read'), 1);
    expect(api.countOf('/messages/17'), 0);
    expect(tester.takeException(), isNull);
  });

  test('页面销毁后晚到的分页响应不再通知监听者', () async {
    final pending = Completer<PagedData<int>>();
    final controller =
        PagedListController<int>(fetchPage: (_, __) => pending.future);
    final loading = controller.load();
    controller.dispose();
    pending.complete(const PagedData(total: 1, list: [17]));
    await loading;
    expect(controller.items, isEmpty);
  });
}
