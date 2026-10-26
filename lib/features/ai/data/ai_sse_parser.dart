// AI 流式 SSE 解析（App 端 E 模块）。
//
// 后端流式端点协议（text/event-stream）：
//   event:message
//   data:{"delta":"内容增量"}
//
//   event:message
//   data:{"done":true,"recordId":123,"quotaUsed":1}
//
//   event:error
//   data:{"code":400,"message":"AI次数不足"}
//
// 本模块把「字节流 → 事件块 → 事件对象」的解析独立出来，便于单元测试；
// 仓库层只负责把 delta 回调给页面、把 done 汇总为结果。
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/network/api_exception.dart';

/// 解析后的一个 SSE 事件。
class AiSseEvent {
  const AiSseEvent(this.event, this.payload);

  /// 事件名（后端约定 message / error；无 event 行默认 message）。
  final String event;

  /// data 行解析出的 JSON 对象；无法解析时为 null。
  final Map<String, dynamic>? payload;

  /// 取 payload 文本字段。
  String text(String field) {
    final p = payload;
    if (p == null) return '';
    final value = p[field];
    return value == null ? '' : value.toString();
  }

  /// 取 payload 数字字段。
  int intValue(String field) {
    final p = payload;
    if (p == null) return 0;
    final value = p[field];
    return value is num ? value.toInt() : 0;
  }
}

/// 消费 SSE 字节流，兼容 LF / CRLF 和跨字节分片，按空行分隔事件并逐块回调。
///
/// `error` 事件直接抛 [ApiException]（后端约定：流中错误不落库、不扣次数）；
/// 其余事件交回 [onEvent] 处理。
Future<void> consumeSseEvents(
  Stream<Uint8List> stream,
  void Function(AiSseEvent event) onEvent,
) async {
  final lines = stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
  final block = StringBuffer();
  await for (final line in lines) {
    if (line.isEmpty) {
      if (_dispatch(block.toString(), onEvent)) return;
      block.clear();
    } else {
      block.writeln(line);
    }
  }
  if (block.isNotEmpty) _dispatch(block.toString(), onEvent);
}

/// 解析并分发单个 SSE 事件块（event:xxx + data:xxx，可多行 data）。
bool _dispatch(
  String block,
  void Function(AiSseEvent event) onEvent,
) {
  String event = 'message';
  final dataLines = <String>[];
  for (final line in block.split('\n')) {
    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trim());
    }
  }
  if (dataLines.isEmpty) return false;
  final payload = _tryParseJson(dataLines.join('\n'));
  // 无法解析的 data 行（非 JSON）视为中间噪声，直接跳过不发事件。
  if (payload == null) return false;
  if (event == 'error') {
    final message = payload['message']?.toString() ?? '';
    throw ApiException(
      message.isEmpty ? 'AI 生成失败，请稍后重试' : message,
      code: payload['code'] is num ? (payload['code'] as num).toInt() : null,
    );
  }
  onEvent(AiSseEvent(event, payload));
  return payload['done'] == true;
}

/// 尝试解析 JSON；失败返回 null。
Map<String, dynamic>? _tryParseJson(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
            ? decoded.map((k, v) => MapEntry('$k', v))
            : null;
  } catch (_) {
    return null;
  }
}
