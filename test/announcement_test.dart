import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/message/data/announcement_repository.dart';
import 'package:script_app/features/message/data/announcement_providers.dart';
import 'package:script_app/features/message/pages/announcement_panel.dart';
import 'package:script_app/features/user_center/data/paged_data.dart';
import 'package:script_app/features/user_center/widgets/paged_list_controller.dart';

class TestAnnouncements extends Fake implements AnnouncementRepository {
  bool failRead = true;
  int reads = 0;
  @override
  Future<PagedData<AnnouncementItem>> list(
          {int pageNum = 1, int pageSize = 10}) async =>
      const PagedData(
          total: 1, list: [AnnouncementItem(noticeId: 17, title: '平台服务升级')]);
  @override
  Future<AnnouncementItem> detail(int id) async =>
      AnnouncementItem(noticeId: id, title: '平台服务升级', content: '服务升级公告正文');
  @override
  Future<int> unreadCount() async => failRead ? 1 : 0;
  @override
  Future<void> markRead(int id) async {
    reads++;
    if (failRead) throw ApiException('网络异常');
  }
}

void main() {
  test('公告解析使用公告ID及真实已读状态，与站内消息ID无关', () {
    final notice = AnnouncementItem.fromJson({
      'noticeId': 17,
      'messageId': 99,
      'noticeTitle': '测试公告',
      'noticeType': '1',
      'isRead': true,
      'noticeContent': '纯文本\n第二行'
    });
    expect(notice.noticeId, 17);
    expect(notice.read, true);
    expect(notice.typeLabel, '公告');
    expect(notice.content, '纯文本\n第二行');
  });

  testWidgets('读取成功后才标记已读，标记失败可以重试并保留正文', (tester) async {
    final repo = TestAnnouncements();
    await tester.pumpWidget(ProviderScope(
        overrides: [announcementRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: AnnouncementPanel()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('平台服务升级'));
    await tester.pumpAndSettle();
    expect(find.text('服务升级公告正文'), findsOneWidget);
    expect(find.text('已读状态更新失败，点击重试'), findsOneWidget);
    expect(repo.reads, 1);
    repo.failRead = false;
    await tester.tap(find.text('已读状态更新失败，点击重试'));
    await tester.pumpAndSettle();
    expect(repo.reads, 2);
    expect(find.text('已读状态更新失败，点击重试'), findsNothing);
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
