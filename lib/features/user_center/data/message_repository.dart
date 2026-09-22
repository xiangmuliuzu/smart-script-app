import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'paged_data.dart';
import 'user_center_models.dart';

/// A5 消息中心与通知偏好数据访问（契约 §1.5）。
class MessageRepository {
  MessageRepository(this._api);

  final ApiClient _api;

  /// 我的消息分页。[type] 为空表示全部类型。
  Future<PagedData<MessageItem>> list({
    String? type,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.messages,
      query: {
        'pageNum': pageNum,
        'pageSize': pageSize,
        if (type != null && type.isNotEmpty) 'type': type,
      },
      parser: _mapParser,
    );
    if (data == null) return const PagedData<MessageItem>(total: 0, list: []);
    return PagedData.parse(data, MessageItem.fromJson);
  }

  Future<UnreadCount> unreadCount() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.messagesUnreadCount,
      parser: _mapParser,
    );
    return UnreadCount.fromJson(data ?? const {});
  }

  Future<MessageItem> detail(int messageId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.messageById(messageId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('消息不存在或已删除');
    return MessageItem.fromJson(data);
  }

  /// 标记单条已读（幂等，重复调用不报错）。
  Future<void> markRead(int messageId) async {
    await _api.put(ApiEndpoints.messageRead(messageId));
  }

  /// 全部已读（幂等）。
  Future<void> markAllRead() async {
    await _api.put(ApiEndpoints.messagesReadAll);
  }

  /// 通知偏好矩阵（渠道 × 类型，未配置的组合由服务端按默认开启展开）。
  Future<List<NotificationPreference>> preferences() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.myNotificationPreferences,
      parser: _mapParser,
    );
    final raw = data?['preferences'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => NotificationPreference.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 保存偏好：只提交发生变化的组合。
  Future<void> updatePreferences(List<NotificationPreference> preferences) async {
    await _api.put(
      ApiEndpoints.myNotificationPreferences,
      data: {'preferences': preferences.map((e) => e.toJson()).toList()},
    );
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}

/// A5 意见反馈数据访问（契约 §1.6）。
class FeedbackRepository {
  FeedbackRepository(this._api);

  final ApiClient _api;

  /// 我的反馈分页。[status] 为空表示不筛选。
  Future<PagedData<FeedbackItem>> list({
    String? status,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.feedback,
      query: {
        'pageNum': pageNum,
        'pageSize': pageSize,
        if (status != null && status.isNotEmpty) 'status': status,
      },
      parser: _mapParser,
    );
    if (data == null) return const PagedData<FeedbackItem>(total: 0, list: []);
    return PagedData.parse(data, FeedbackItem.fromJson);
  }

  Future<FeedbackItem> detail(int feedbackId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.feedbackById(feedbackId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('反馈不存在');
    return FeedbackItem.fromJson(data);
  }

  /// 提交反馈，返回新记录标识。
  Future<int> create({
    required String category,
    required String content,
    String? attachmentRef,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.feedback,
      data: {
        'category': category,
        'content': content,
        if (attachmentRef != null && attachmentRef.isNotEmpty) 'attachmentRef': attachmentRef,
      },
      parser: _mapParser,
    );
    final id = (data?['feedbackId'] as num?)?.toInt() ?? 0;
    if (id <= 0) throw ApiException('提交失败，请稍后重试');
    return id;
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}
