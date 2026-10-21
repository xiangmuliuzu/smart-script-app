import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'chat_models.dart';

/// A3 聊天域数据访问层。
///
/// 封装会话列表、消息收发、已读/未读、定型文模板等 API 调用。
class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  // ==================== 会话管理 ====================

  /// 获取我的会话列表。
  ///
  /// [sessionType] 可选筛选：ADMIN / TRADE / null（全部）。
  Future<PagedData<ChatSessionWithPeer>> listSessions({
    String? sessionType,
    int? status,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.chatSessions,
      query: _compact({
        'sessionType': sessionType,
        'status': status,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取会话列表失败');
    return PagedData.parse<ChatSessionWithPeer>(
      data,
      ChatSessionWithPeer.fromVo,
    );
  }

  /// 创建 ADMIN 类型会话（与管理员沟通）。
  Future<ChatSessionWithPeer> createAdminSession({
    String? businessType,
    int? businessId,
    String? businessName,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.chatSessions,
      data: _compact({
        'sessionType': 'ADMIN',
        'businessType': businessType,
        'businessId': businessId,
        'businessName': businessName,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('创建会话失败');
    return ChatSessionWithPeer.fromVo(data);
  }

  /// 创建 TRADE 类型会话（买卖双方交易会话）。
  ///
  /// 通过询盘ID创建，后端自动确定买卖双方。
  Future<ChatSessionWithPeer> createTradeSession(int inquiryId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '${ApiEndpoints.tradeChatSessions}?inquiryId=$inquiryId',
      parser: _mapParser,
    );
    if (data == null) throw ApiException('创建交易会话失败');
    return ChatSessionWithPeer.fromVo(data);
  }

  /// 获取单个会话详情（含 sessionType、inquiryId 等）。
  Future<ChatSessionWithPeer> getSessionDetail(int sessionId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.chatSessionDetail(sessionId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取会话详情失败');
    return ChatSessionWithPeer.fromVo(data);
  }

  // ==================== 消息管理 ====================

  /// 获取会话内历史消息。
  Future<PagedData<ChatMessage>> listMessages(int sessionId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.chatMessages(sessionId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取消息列表失败');
    return PagedData.parse<ChatMessage>(data, ChatMessage.fromJson);
  }

  /// 发送文字消息。
  Future<ChatMessage> sendMessage(int sessionId, String content) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.chatMessages(sessionId),
      data: {'content': content},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('发送消息失败');
    return ChatMessage.fromJson(data);
  }

  // ==================== 已读/未读 ====================

  /// 标记会话已读。
  Future<void> markRead(int sessionId) async {
    await _api.put<Map<String, dynamic>>(
      ApiEndpoints.chatMarkRead(sessionId),
      parser: _mapParser,
    );
  }

  /// 获取未读消息总数。
  Future<int> getUnreadCount() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.chatUnreadCount,
      parser: _mapParser,
    );
    if (data == null) return 0;
    return (data['chatUnread'] as num?)?.toInt() ?? 0;
  }

  // ==================== 会话状态 ====================

  /// 重新打开已结束的会话。
  Future<void> reopenSession(int sessionId) async {
    await _api.put<Map<String, dynamic>>(
      '${ApiEndpoints.chatChangeStatus(sessionId)}?action=reopen',
      parser: _mapParser,
    );
  }

  // ==================== 定型文模板 ====================

  /// 获取交易会话定型文模板列表。
  Future<List<TradeTemplate>> listTradeTemplates() async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.chatTradeTemplates,
      parser: (raw) => raw is List ? raw : <dynamic>[],
    );
    if (data == null) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(TradeTemplate.fromJson)
        .toList();
  }

  // ==================== 工具方法 ====================

  Map<String, dynamic> _compact(Map<String, dynamic> map) {
    return Map.fromEntries(
      map.entries.where((e) => e.value != null),
    );
  }

  Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw ApiException('响应格式错误');
  }
}
