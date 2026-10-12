import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/message/pages/message_list_page.dart';
import 'package:script_app/features/user_center/widgets/paged_list_controller.dart';
import 'package:script_app/features/user_center/data/paged_data.dart';
import 'support/scripted_api.dart';

void main() {
  test('自动接收在途时不并发追加分页，完成后仍可继续翻页', () async {
    final pending = Completer<PagedData<int>>();
    var calls = 0;
    final controller = PagedListController<int>(
        pageSize: 1,
        fetchPage: (page, _) async {
          calls++;
          if (calls == 2) return pending.future;
          return PagedData(total: 2, list: [page]);
        });
    await controller.load();
    final refreshing = controller.refreshSilently();
    await controller.loadMore();
    expect(calls, 2);
    pending.complete(const PagedData(total: 2, list: [1]));
    await refreshing;
    await controller.loadMore();
    expect(controller.items, [1, 2]);
    controller.dispose();
  });

  testWidgets('已打开的空消息中心自动接收后续管理员通知', (tester) async {
    final api = ScriptedApi();
    bool delivered = false;
    api.reply(
        '/messages/unread-count',
        Envelope.ok({
          'total': 1,
          'byType': {'SYSTEM': 1}
        }));
    api.reply('/announcements', Envelope.ok({'total': 0, 'list': []}));
    api.handle(
        '/messages',
        (_) => Envelope.ok({
              'total': delivered ? 1 : 0,
              'list': delivered
                  ? [
                      {
                        'messageId': 18,
                        'type': 'SYSTEM',
                        'title': '管理员后续通知',
                        'summary': '收到正文摘要',
                        'read': false
                      }
                    ]
                  : []
            }));
    await tester.pumpWidget(ProviderScope(
        overrides: [api.override],
        child: const MaterialApp(home: MessageListPage())));
    await tester.pumpAndSettle();
    expect(find.text('暂无消息'), findsOneWidget);
    delivered = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('管理员后续通知'), findsOneWidget);
    expect(find.text('收到正文摘要'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('空消息中心保留手动刷新入口', (tester) async {
    final api = ScriptedApi();
    api.reply('/messages', Envelope.ok({'total': 0, 'list': []}));
    api.reply('/announcements', Envelope.ok({'total': 0, 'list': []}));
    await tester.pumpWidget(ProviderScope(
        overrides: [api.override],
        child: const MaterialApp(home: MessageListPage())));
    await tester.pumpAndSettle();
    final before = api.countOf('/messages');
    await tester.tap(find.byTooltip('刷新通知'));
    await tester.pumpAndSettle();
    expect(api.countOf('/messages'), greaterThan(before));
    await tester.pumpWidget(const SizedBox());
  });

  test('静默刷新失败保留消息，手动刷新使旧自动响应作废', () async {
    final stale = Completer<PagedData<int>>();
    int calls = 0;
    final controller = PagedListController<int>(fetchPage: (_, __) async {
      calls++;
      if (calls == 2) throw Exception('临时断网');
      if (calls == 3) return stale.future;
      return PagedData(total: 1, list: [calls]);
    });
    await controller.load();
    await controller.refreshSilently();
    expect(controller.items, [1]);
    final pending = controller.refreshSilently();
    await controller.load(refresh: true);
    stale.complete(const PagedData(total: 1, list: [99]));
    await pending;
    expect(controller.items, [4]);
    controller.dispose();
  });
}
