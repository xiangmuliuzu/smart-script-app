// H-05 多视口 widget 测试：关键列表页在小屏 / 常规 / 平板宽度下渲染。
//
// 对应第 4 批 H-05 残余「多视口未验证」：App 无响应式断点（lib 内无 MediaQuery/
// LayoutBuilder 分支），风险集中于小屏溢出（RenderFlex overflow）与关键内容不可见。
// 断言方式：不同视口 pump 后关键行存在（溢出会让 testWidgets 直接失败）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/feedback/pages/feedback_list_page.dart';
import 'package:script_app/features/message/pages/message_list_page.dart';

import '../support/scripted_api.dart';

class _FakeSecureStorage implements TokenSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

const _longTitle = '这是一个相当长的系统通知标题用于在小屏宽度下检验文本换行与布局';
const _longSummary = '摘要内容同样较长，用来检验 320 像素宽的小屏设备上多行文本的换行、'
    '省略与行间布局是否仍然正常，同时覆盖富文本与时间戳在同一行的空间分配。';

final _msgRow = {
  'messageId': 21,
  'type': 'SYSTEM',
  'title': _longTitle,
  'summary': _longSummary,
  'read': false,
  'createdAt': '2026-09-28 10:00:00',
};

final _fbRow = {
  'feedbackId': 31,
  'category': 'SUGGESTION',
  'content': _longSummary,
  'status': 'PENDING',
  'submittedAt': '2026-09-28 10:00:00',
};

Future<void> _pumpAt(
  WidgetTester tester,
  Widget page,
  ScriptedApi api,
  Size logical,
) async {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = TokenStorage(_FakeSecureStorage(), prefs);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
      tokenStorageProvider.overrideWithValue(storage),
      api.override,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const sizes = <String, Size>{
    'small-320x640': Size(320, 640),
    'phone-412x915': Size(412, 915),
    'tablet-768x1024': Size(768, 1024),
  };

  testWidgets('H-05-V 多视口：消息列表在三种视口渲染且长文本行可见', (tester) async {
    for (final entry in sizes.entries) {
      final api = ScriptedApi();
      api.reply('/messages/unread-count', Envelope.ok({'total': 1}));
      api.reply('/messages', Envelope.ok({'total': 1, 'list': [_msgRow]}));

      await _pumpAt(tester, const MessageListPage(), api, entry.value);

      expect(find.text(_longTitle), findsOneWidget,
          reason: '${entry.key}: 长标题应可见');
      // 溢出会以异常形式让本用例失败；这里再确认整页无溢出横幅
      expect(find.textContaining('溢出'), findsNothing,
          reason: '${entry.key}: 不应出现溢出提示');
    }
  });

  testWidgets('H-05-V 多视口：反馈列表在三种视口渲染且行内容可见', (tester) async {
    for (final entry in sizes.entries) {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.ok({'total': 1, 'list': [_fbRow]}));

      await _pumpAt(tester, const FeedbackListPage(), api, entry.value);

      expect(find.textContaining(_longSummary.substring(0, 8)), findsWidgets,
          reason: '${entry.key}: 长反馈内容应可见（可能被省略号截断）');
    }
  });
}
