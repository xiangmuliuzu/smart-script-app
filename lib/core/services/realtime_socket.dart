import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import '../providers/app_providers.dart';
import '../providers/auth_providers.dart';

/// 一条服务端下发的实时事件。
///
/// 帧只携带事件类型与定位 id，正文一律回查业务接口，因此丢帧或断开都不会造成数据缺失。
class RealtimeEvent {
  const RealtimeEvent(this.type, this.payload);

  final String type;
  final Map<String, dynamic> payload;
}

/// 解析一帧文本；非 JSON 或缺少 type 的帧直接忽略（服务端不会主动发这种帧）。
RealtimeEvent? parseRealtimeFrame(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final type = decoded['type'];
    if (type is! String) return null;
    return RealtimeEvent(type, Map<String, dynamic>.from(decoded));
  } catch (_) {
    return null;
  }
}

/// 站内实时通知长连接。
///
/// 与 HTTP 请求共用同一套登录令牌。令牌走 `Authorization` 请求头而不是查询参数：
/// 网址会被服务端访问日志原文记录，令牌不该出现在那里。
///
/// 断线不影响正确性：链路恢复后发出 `reconnect` 事件，订阅方据此补拉一次；
/// 事件丢失或连接不可用时，各页面按原有轮询节奏兜底。
class RealtimeSocket {
  /// [readToken] 在真正建连时才求值：构造这个单例不该把令牌存储拽起来，
  /// 否则任何读到它的 widget 测试都得先替令牌存储做插件 mock。
  RealtimeSocket({required String? Function() readToken})
      : _readToken = readToken;

  static const Duration heartbeatInterval = Duration(seconds: 25);
  static const Duration pongTimeout = Duration(seconds: 35);
  static const Duration baseBackoff = Duration(seconds: 1);
  static const Duration maxBackoff = Duration(seconds: 30);

  /// 服务端策略关闭（登录会话已失效）。继续重连只会反复撞墙，
  /// 交给 HTTP 层的会话失效流程把用户带回登录页。
  static const int closeCodePolicyViolation = 1008;

  final String? Function() _readToken;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _pongTimer;
  Timer? _reconnectTimer;
  int _attempt = 0;

  /// 每次主动断开/重建自增，用于丢弃迟到的握手结果，避免旧连接回调污染新状态。
  int _generation = 0;
  bool _open = false;
  bool _connecting = false;
  bool _everConnected = false;
  bool _closedByApp = false;
  bool _disposed = false;

  Stream<RealtimeEvent> get events => _events.stream;

  bool get isConnected => _open;

  /// 长连接地址：与 REST 接口同源，只把 http(s) 换成 ws(s) 并换掉路径前缀。
  static Uri endpoint() {
    final base = Uri.parse(AppConfig.baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/notify',
    );
  }

  void connect() {
    if (_disposed || _channel != null || _connecting) return;
    final token = _readToken();
    if (token == null || token.isEmpty) return;
    _closedByApp = false;
    _connecting = true;
    final generation = _generation;
    WebSocket.connect(
      endpoint().toString(),
      headers: <String, dynamic>{'Authorization': 'Bearer $token'},
    ).then((socket) {
      if (_disposed || generation != _generation) {
        unawaited(socket.close());
        return;
      }
      _connecting = false;
      _attach(IOWebSocketChannel(socket));
    }).catchError((Object _) {
      if (_disposed || generation != _generation) return;
      _connecting = false;
      _scheduleReconnect();
    });
  }

  /// 主动关闭（退出登录）。之后不再自动重连，直到下一次 [connect]。
  void close() {
    _closedByApp = true;
    _stopHeartbeat();
    _cancelReconnect();
    _teardown();
    _everConnected = false;
  }

  Future<void> dispose() async {
    _disposed = true;
    close();
    await _events.close();
  }

  void _attach(WebSocketChannel channel) {
    _channel = channel;
    _subscription = channel.stream.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
      cancelOnError: true,
    );
    _open = true;
    _attempt = 0;
    _startHeartbeat();
    _emit('connected', const <String, dynamic>{});
    // 首次建连时页面本来就会拉一次，只有重连才需要通知订阅方补拉
    if (_everConnected) _emit('reconnect', const <String, dynamic>{});
    _everConnected = true;
  }

  void _onFrame(dynamic data) {
    if (data is! String) return;
    final event = parseRealtimeFrame(data);
    if (event == null) return;
    if (event.type == 'pong') {
      _clearPongTimeout();
      return;
    }
    _emit(event.type, event.payload);
  }

  void _onClosed() {
    final code = _channel?.closeCode;
    _teardown();
    _emit('disconnected', <String, dynamic>{'code': code});
    if (_closedByApp || _disposed) return;
    if (code == closeCodePolicyViolation) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _closedByApp || _reconnectTimer != null) return;
    final factor = 1 << _attempt.clamp(0, 5);
    var delay = baseBackoff * factor;
    if (delay > maxBackoff) delay = maxBackoff;
    _attempt += 1;
    // 加抖动：避免服务重启后所有端在同一秒齐刷刷重连。
    _reconnectTimer = Timer(
      delay + Duration(milliseconds: 200 + _jitterMillis()),
      () {
        _reconnectTimer = null;
        connect();
      },
    );
  }

  static int _jitterMillis() =>
      DateTime.now().microsecondsSinceEpoch.remainder(600);

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      final channel = _channel;
      if (!_open || channel == null) return;
      try {
        channel.sink.add(jsonEncode(const <String, String>{'type': 'ping'}));
      } catch (_) {
        return;
      }
      _clearPongTimeout();
      _pongTimer = Timer(pongTimeout, () {
        // 长时间没有应答说明链路已经不可用（切网络后 TCP 不会立刻报错），主动断开重连。
        try {
          channel.sink.close();
        } catch (_) {}
      });
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _clearPongTimeout();
  }

  void _clearPongTimeout() {
    _pongTimer?.cancel();
    _pongTimer = null;
  }

  void _teardown() {
    _generation += 1;
    _open = false;
    _connecting = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        channel.sink.close();
      } catch (_) {}
    }
  }

  void _emit(String type, Map<String, dynamic> payload) {
    if (_events.isClosed) return;
    _events.add(RealtimeEvent(type, payload));
  }
}

/// 会话级单例：登录后建连、退出即断开。
///
/// 测试环境（flutter test 注入 FLUTTER_TEST=true）不建连，避免挂起的定时器
/// 让 widget 测试报 "A Timer is still pending"，与消息轮询保持同一口径。
final realtimeSocketProvider = Provider<RealtimeSocket>((ref) {
  final socket =
      RealtimeSocket(readToken: () => ref.read(tokenStorageProvider).token);
  if (Platform.environment['FLUTTER_TEST'] != 'true') {
    ref.listen<bool>(
      authControllerProvider.select((state) => state.isAuthenticated),
      (previous, next) {
        if (next) {
          socket.connect();
        } else {
          socket.close();
        }
      },
    );
  }
  ref.onDispose(() => unawaited(socket.dispose()));
  return socket;
});
