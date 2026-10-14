import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../user_center/data/paged_data.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// A3 聊天域依赖注入。

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider)),
);

// ==================== 会话列表 Providers ====================

/// 会话列表查询参数
class SessionListParams {
  final String? sessionType;  // ADMIN / TRADE / null（全部）
  final int? status;

  const SessionListParams({this.sessionType, this.status});

  SessionListParams copyWith({String? sessionType, int? status}) {
    return SessionListParams(
      sessionType: sessionType ?? this.sessionType,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SessionListParams &&
        other.sessionType == sessionType &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(sessionType, status);
}

/// 会话列表
final sessionListProvider = FutureProvider.autoDispose
    .family<PagedData<ChatSessionWithPeer>, SessionListParams>(
  (ref, params) => ref.watch(chatRepositoryProvider).listSessions(
        sessionType: params.sessionType,
        status: params.status,
      ),
);

// ==================== 消息列表 Providers ====================

/// 消息列表（按会话ID）
final messagesProvider = FutureProvider.autoDispose.family<PagedData<ChatMessage>, int>(
  (ref, sessionId) => ref.watch(chatRepositoryProvider).listMessages(sessionId),
);

/// 未读消息总数
final chatUnreadCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.getUnreadCount();
});
