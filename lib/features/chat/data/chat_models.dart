/// A3 聊天域数据模型（会话 + 消息）。
///
/// 字段对齐后端 domain：ChatSession / ChatMessage。
/// 两种会话类型：ADMIN（用户与管理员沟通）/ TRADE（买卖双方交易沟通）。

// ==================== 会话类型 ====================

/// 会话类型常量
class SessionType {
  static const String admin = 'ADMIN';   // 咨询会话（用户与管理员）
  static const String trade = 'TRADE';   // 交易会话（买卖双方）
  static const String chat = 'CHAT';     // 旧数据兼容（等同于 ADMIN）

  static String label(String? type) {
    switch (type) {
      case admin: return '咨询会话';
      case trade: return '交易会话';
      case chat: return '咨询会话';  // 旧 CHAT 类型归入咨询
      default: return type ?? '未知';
    }
  }

  /// 判断是否为咨询类会话（ADMIN 或旧 CHAT）
  static bool isAdminType(String? type) =>
      type == admin || type == chat;
}

/// 会话状态
class SessionStatus {
  static const int pending = 0;   // 进行中
  static const int closed = 2;    // 已结束

  static String label(int? status) {
    switch (status) {
      case pending: return '进行中';
      case closed: return '已结束';
      default: return '未知';
    }
  }
}

// ==================== 聊天会话 ====================

/// 聊天会话
class ChatSession {
  const ChatSession({
    required this.sessionId,
    this.sessionType,
    this.inquiryId,
    required this.user1Id,
    required this.user2Id,
    this.user1Name,
    this.user2Name,
    this.user1Avatar,
    this.user2Avatar,
    this.lastMessage,
    this.lastMessageTime,
    this.user1Unread = 0,
    this.user2Unread = 0,
    this.status = 0,
    this.businessType,
    this.businessId,
    this.businessName,
    this.createdAt,
  });

  final int sessionId;
  final String? sessionType;   // ADMIN / TRADE
  final int? inquiryId;
  final int user1Id;
  final int user2Id;
  final String? user1Name;
  final String? user2Name;
  final String? user1Avatar;
  final String? user2Avatar;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int user1Unread;
  final int user2Unread;
  final int status;            // 0=进行中 2=已结束
  final String? businessType;
  final int? businessId;
  final String? businessName;
  final DateTime? createdAt;

  bool get isClosed => status == SessionStatus.closed;

  /// 获取对方信息（根据当前用户ID判断）
  int peerId(int currentUserId) =>
      currentUserId == user1Id ? user2Id : user1Id;

  String? peerName(int currentUserId) =>
      currentUserId == user1Id ? user2Name : user1Name;

  String? peerAvatar(int currentUserId) =>
      currentUserId == user1Id ? user2Avatar : user1Avatar;

  /// 获取当前用户未读数
  int unreadCount(int currentUserId) =>
      currentUserId == user1Id ? user1Unread : user2Unread;

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    sessionId: (json['sessionId'] as num?)?.toInt() ?? 0,
    sessionType: json['sessionType'] as String?,
    inquiryId: (json['inquiryId'] as num?)?.toInt(),
    user1Id: (json['user1Id'] as num?)?.toInt() ?? 0,
    user2Id: (json['user2Id'] as num?)?.toInt() ?? 0,
    user1Name: json['user1Name'] as String?,
    user2Name: json['user2Name'] as String?,
    user1Avatar: json['user1Avatar'] as String?,
    user2Avatar: json['user2Avatar'] as String?,
    lastMessage: json['lastMessage'] as String?,
    lastMessageTime: _parseDateTime(json['lastMessageTime']),
    user1Unread: (json['user1Unread'] as num?)?.toInt() ?? 0,
    user2Unread: (json['user2Unread'] as num?)?.toInt() ?? 0,
    status: (json['status'] as num?)?.toInt() ?? 0,
    businessType: json['businessType'] as String?,
    businessId: (json['businessId'] as num?)?.toInt(),
    businessName: json['businessName'] as String?,
    createdAt: _parseDateTime(json['createdAt']),
  );

  /// 从后端 AppChatController 的 VO 格式解析（peerId/peerName/peerAvatar）
  factory ChatSession.fromVo(Map<String, dynamic> json) => ChatSession(
    sessionId: (json['sessionId'] as num?)?.toInt() ?? 0,
    sessionType: json['sessionType'] as String?,
    inquiryId: (json['inquiryId'] as num?)?.toInt(),
    user1Id: 0,  // VO 不直接暴露 user1Id/user2Id
    user2Id: 0,
    user1Name: null,
    user2Name: null,
    user1Avatar: null,
    user2Avatar: null,
    lastMessage: json['lastMessage'] as String?,
    lastMessageTime: _parseDateTime(json['lastMessageTime']),
    user1Unread: 0,
    user2Unread: 0,
    status: (json['status'] as num?)?.toInt() ?? 0,
    businessType: json['businessType'] as String?,
    businessId: (json['businessId'] as num?)?.toInt(),
    businessName: json['businessName'] as String?,
    createdAt: _parseDateTime(json['createdAt']),
  );
}

/// 带对方信息的会话（用于列表展示）
class ChatSessionWithPeer {
  const ChatSessionWithPeer({
    required this.session,
    required this.peerId,
    this.peerName,
    this.peerAvatar,
    this.unread = 0,
  });

  final ChatSession session;
  final int peerId;
  final String? peerName;
  final String? peerAvatar;
  final int unread;

  factory ChatSessionWithPeer.fromVo(Map<String, dynamic> json) {
    final session = ChatSession(
      sessionId: (json['sessionId'] as num?)?.toInt() ?? 0,
      sessionType: json['sessionType'] as String?,
      inquiryId: (json['inquiryId'] as num?)?.toInt(),
      user1Id: 0,
      user2Id: 0,
      lastMessage: json['lastMessage'] as String?,
      lastMessageTime: _parseDateTime(json['lastMessageTime']),
      status: (json['status'] as num?)?.toInt() ?? 0,
      businessType: json['businessType'] as String?,
      businessId: (json['businessId'] as num?)?.toInt(),
      businessName: json['businessName'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
    );
    return ChatSessionWithPeer(
      session: session,
      peerId: (json['peerId'] as num?)?.toInt() ?? 0,
      peerName: json['peerName'] as String?,
      peerAvatar: json['peerAvatar'] as String?,
      unread: (json['unread'] as num?)?.toInt() ?? 0,
    );
  }
}

// ==================== 聊天消息 ====================

/// 消息类型
class MessageType {
  static const String text = 'TEXT';     // 文字消息
  static const String system = 'SYSTEM'; // 系统提示
}

/// 聊天消息
class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.sessionId,
    required this.senderId,
    this.senderName,
    this.senderAvatar,
    this.content = '',
    this.msgType = MessageType.text,
    this.isRead = false,
    this.createdAt,
  });

  final int messageId;
  final int sessionId;
  final int senderId;
  final String? senderName;
  final String? senderAvatar;
  final String content;
  final String msgType;   // TEXT / SYSTEM
  final bool isRead;
  final DateTime? createdAt;

  bool get isSystem => msgType == MessageType.system;

  /// 判断是否为当前用户发送的消息
  bool isMine(int currentUserId) => senderId == currentUserId;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    messageId: (json['messageId'] as num?)?.toInt() ?? 0,
    sessionId: (json['sessionId'] as num?)?.toInt() ?? 0,
    senderId: (json['senderId'] as num?)?.toInt() ?? 0,
    senderName: json['senderName'] as String?,
    senderAvatar: json['senderAvatar'] as String?,
    content: json['content'] as String? ?? '',
    msgType: json['msgType'] as String? ?? MessageType.text,
    isRead: json['isRead'] as bool? ?? false,
    createdAt: _parseDateTime(json['createdAt']),
  );
}

// ==================== 工具函数 ====================

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return null;
}
