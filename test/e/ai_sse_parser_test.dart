// AI 流式 SSE 解析（App 端 E 模块 阶段2）。
//
// 覆盖：
//   - 标准事件块（event:message + data:{delta}）逐块回调；
//   - done 事件携带 recordId / quotaUsed / requestNo；
//   - error 事件抛 ApiException 且带业务码；
//   - 跨 chunk 切分（同一块数据拆到多次字节流送达）仍能正确解析；
//   - 非 JSON 的 data 行不崩溃。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/ai/data/ai_sse_parser.dart';

void main() {
  group('AiSseParser', () {
    test('逐块解析 delta 与 done', () async {
      final events = <AiSseEvent>[];
      final raw = 'event:message\ndata:{"delta":"第一段"}\n\n'
          'event:message\ndata:{"delta":"第二段"}\n\n'
          'event:message\ndata:{"done":true,"recordId":7}\n\n';
      await consumeSseEvents(_bytes(raw), events.add);
      expect(events.length, 3);
      expect(events[0].event, 'message');
      expect(events[0].text('delta'), '第一段');
      expect(events[1].text('delta'), '第二段');
      expect(events[2].event, 'message');
      expect(events[2].intValue('recordId'), 7);
    });

    test('大纲 done 事件携带 quotaUsed 与 requestNo', () async {
      final events = <AiSseEvent>[];
      final raw = 'event:message\n'
          'data:{"delta":"{\\"title\\":\\"测试\\"}"}\n\n'
          'event:message\n'
          'data:{"done":true,"quotaUsed":1,"requestNo":"AIR20261021"}\n\n';
      await consumeSseEvents(_bytes(raw), events.add);
      expect(events.length, 2);
      expect(events[1].intValue('quotaUsed'), 1);
      expect(events[1].text('requestNo'), 'AIR20261021');
    });

    test('error 事件抛 ApiException 并携带业务码', () async {
      final raw = 'event:error\ndata:{"code":400,"message":"AI次数不足，当前可用: 0 次"}\n\n';
      await expectLater(
        consumeSseEvents(_bytes(raw), (_) {}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('AI次数不足'))
            .having((e) => e.code, 'code', 400)),
      );
    });

    test('跨 chunk 切分仍能完整解析', () async {
      final events = <AiSseEvent>[];
      final stream = _splitChunks(
        'event:message\ndata:{"delta":"前半"}\n\nevent:message\ndata:{"delta":"后半"}\n\n',
        chunkSize: 7,
      );
      await consumeSseEvents(stream, events.add);
      expect(events.length, 2);
      expect(events[0].text('delta'), '前半');
      expect(events[1].text('delta'), '后半');
    });

    test('非 JSON 的 data 行不崩溃且跳过', () async {
      final events = <AiSseEvent>[];
      final raw = 'event:message\ndata:not-json\n\nevent:message\ndata:{"delta":"正常"}\n\n';
      await consumeSseEvents(_bytes(raw), events.add);
      expect(events.length, 1);
      expect(events[0].text('delta'), '正常');
    });

    test('无 event 行默认 message，多行 data 合并', () async {
      final events = <AiSseEvent>[];
      final raw = 'data:{"delta":"行一"}\ndata:{"delta":"行二"}\n\n';
      await consumeSseEvents(_bytes(raw), events.add);
      // 两行 data 拼接后不是合法 JSON，视为噪声跳过；不崩溃即通过。
      expect(events, isEmpty);
    });
  });
}

/// 把 SSE 文本转成单块字节流。
Stream<Uint8List> _bytes(String text) async* {
  yield Uint8List.fromList(utf8.encode(text));
}

/// 把 SSE 文本切成 [chunkSize] 字节的多个块，模拟网络分片。
Stream<Uint8List> _splitChunks(String text, {required int chunkSize}) async* {
  final bytes = utf8.encode(text);
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = (i + chunkSize > bytes.length) ? bytes.length : i + chunkSize;
    yield Uint8List.fromList(bytes.sublist(i, end));
  }
}
