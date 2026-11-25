import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/friendly_error.dart';
import '../../core/providers/app_providers.dart';
import '../ai/data/ai_sse_parser.dart';

const sourcingLimitMessage = '今日 AI 选本咨询次数已达上限，请明天再来或直接联系平台客服';

final sourcingAgentRepositoryProvider = Provider<SourcingAgentRepository>(
  (ref) => SourcingAgentRepository(ref.watch(apiClientProvider)),
);

class SourcingAgentRepository {
  SourcingAgentRepository(this._api);

  final ApiClient _api;
  static const _sessions = ApiEndpoints.sourcingAgentSessions;

  Future<List<SourcingSession>> listSessions() async =>
      await _api.get<List<SourcingSession>>(
        _sessions,
        parser: (raw) =>
            sourcingRows(raw).map(SourcingSession.fromJson).toList(),
      ) ??
      const [];

  Future<SourcingSession> createSession() async {
    final session = await _api.post<SourcingSession>(
      _sessions,
      data: const <String, dynamic>{},
      parser: (raw) => SourcingSession.fromJson(_sourcingMap(raw)),
    );
    if (session == null || session.id <= 0) {
      throw ApiException('未能创建选本会话');
    }
    return session;
  }

  Future<List<SourcingMessage>> listMessages(int sessionId) async =>
      await _api.get<List<SourcingMessage>>(
        '$_sessions/$sessionId/messages',
        parser: (raw) =>
            sourcingRows(raw).map(SourcingMessage.fromJson).toList(),
      ) ??
      const [];

  Future<void> deleteSession(int sessionId) async {
    await _api.delete<dynamic>('$_sessions/$sessionId');
  }

  Future<void> chat(
    int sessionId,
    String message, {
    required CancelToken cancelToken,
    required void Function(AiSseEvent) onEvent,
  }) async {
    final response = await _api.postStream(
      '$_sessions/$sessionId/chat/stream',
      data: {'message': message},
      cancelToken: cancelToken,
      receiveTimeout: const Duration(minutes: 3),
    );
    final type = response.headers[Headers.contentTypeHeader]?.join(';') ?? '';
    final status = response.statusCode;
    if (status != 200 || !type.contains('text/event-stream')) {
      await response.stream.listen(null).cancel();
      throw ApiException(
        status == 429
            ? sourcingLimitMessage
            : FriendlyError.messageForStatus(status) ?? '选本回复中断，请稍后重试',
        code: status,
      );
    }
    var done = false;
    void dispatch(AiSseEvent event) {
      if (cancelToken.isCancelled) return;
      if (event.event == 'done') done = true;
      onEvent(event);
    }

    await consumeSseEvents(response.stream, dispatch, onErrorEvent: dispatch);
    if (!done && !cancelToken.isCancelled) {
      throw ApiException('选本回复中断，请稍后重试');
    }
  }
}

class SourcingSession {
  const SourcingSession(this.id, this.title);
  final int id;
  final String title;

  factory SourcingSession.fromJson(Map<String, dynamic> json) =>
      SourcingSession(
          sourcingInt(json['sessionId']), json['title']?.toString() ?? '新选本对话');
}

class SourcingMessage {
  const SourcingMessage(this.isUser, this.content, this.cards);
  final bool isUser;
  final String content;
  final List<SourcingCard> cards;

  factory SourcingMessage.fromJson(Map<String, dynamic> json) =>
      SourcingMessage(
        json['role'] == 'user',
        json['content']?.toString() ?? '',
        sourcingRows(json['cards']).map(SourcingCard.fromJson).toList(),
      );
}

class SourcingCard {
  const SourcingCard(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;

  factory SourcingCard.fromJson(Map<String, dynamic> json) => SourcingCard(
      json['type']?.toString() ?? '', _sourcingMap(json['payload']));
}

int sourcingInt(dynamic value) =>
    value is int ? value : int.tryParse('$value') ?? 0;

List<Map<String, dynamic>> sourcingRows(dynamic value) => value is List
    ? value.whereType<Map>().map(_sourcingMap).toList()
    : const [];

Map<String, dynamic> _sourcingMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
