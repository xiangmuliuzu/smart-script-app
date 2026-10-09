import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/user_center/data/message_repository.dart';

/// 可选本地联调：会话文件由测试夹具生成，凭证不写入仓库或命令行。
void main() {
  final sessionPath =
      Platform.environment['MESSAGE_DELIVERY_SESSION_FILE'] ?? '';
  test('App真实消息客户端接收管理员通知，PC/App已读共享且其他用户隔离', () async {
    final session = jsonDecode(await File(sessionPath).readAsString()) as Map;
    expect(session['baseUrl'], 'http://127.0.0.1:8080/api/v1');
    MessageRepository repository(String token) =>
        MessageRepository(ApiClient(Dio(BaseOptions(
            baseUrl: session['baseUrl'] as String,
            headers: {'Authorization': 'Bearer $token'}))));
    final app = repository(session['appToken'] as String);
    final pc = repository(session['pcToken'] as String);
    final other = repository(session['otherToken'] as String);
    final id = session['messageId'] as int;
    final rows = await app.list();
    expect(
        rows.list.any(
            (item) => item.messageId == id && item.title == session['title']),
        true);
    expect((await app.detail(id)).content, '管理员通知正文');
    expect((await app.unreadCount()).total, greaterThan(0));
    await app.markRead(id);
    expect((await pc.detail(id)).read, true);
    expect((await other.detail(id)).read, false);
  }, skip: sessionPath.isEmpty ? '仅在提供本地测试夹具会话时运行' : false);
  final unifiedPath = Platform.environment['UNIFIED_INBOX_SESSION_FILE'] ?? '';
  test('真实合并接口的公告归入系统，重复编号详情与已读保持独立', () async {
    final session = jsonDecode(await File(unifiedPath).readAsString()) as Map;
    MessageRepository repository(String token) =>
        MessageRepository(ApiClient(Dio(BaseOptions(
            baseUrl: session['baseUrl'] as String,
            headers: {'Authorization': 'Bearer $token'}))));
    final app = repository(session['appToken'] as String);
    final pc = repository(session['pcToken'] as String);
    final other = repository(session['otherToken'] as String);
    final id = session['messageId'] as int;
    final rows = await app.list(
        type: 'SYSTEM', includeAnnouncements: true, pageSize: 100);
    expect(
        rows.list
            .where((item) => item.messageId == id)
            .map((item) => item.source)
            .toSet(),
        {'ANNOUNCEMENT', 'NOTIFICATION'});
    expect((await app.detail(id, source: 'ANNOUNCEMENT')).content, '历史公告正文');
    expect((await app.detail(id)).content, '管理员通知正文');
    final before = (await app.unreadCount(includeAnnouncements: true)).total;
    await app.markRead(id, source: 'ANNOUNCEMENT');
    expect((await pc.detail(id, source: 'ANNOUNCEMENT')).read, true);
    expect((await app.detail(id)).read, false);
    expect((await other.detail(id, source: 'ANNOUNCEMENT')).read, false);
    expect(
        (await app.unreadCount(includeAnnouncements: true)).total, before - 1);
  }, skip: unifiedPath.isEmpty ? '仅在提供本地合并收件箱夹具会话时运行' : false);
}
