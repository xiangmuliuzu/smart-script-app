/// A5 用户中心模型（契约 A5-USER-CENTER-CONTRACT-v1）。
///
/// 只映射后端已定义的字段，不新增本地推断字段。
/// 所有对外展示的手机号、姓名、证件号都是服务端已脱敏的值，客户端不还原。
library;

/// 个人资料（§1.2）。
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.userType,
    this.nickname,
    this.avatar,
    this.phoneMasked,
    this.realNameStatus = 'NOT_SUBMITTED',
  });

  final int userId;
  final String userType;
  final String? nickname;
  final String? avatar;
  final String? phoneMasked;
  final String realNameStatus;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        userType: json['userType'] as String? ?? '01',
        nickname: json['nickname'] as String?,
        avatar: json['avatar'] as String?,
        phoneMasked: json['phoneMasked'] as String?,
        realNameStatus: json['realNameStatus'] as String? ?? 'NOT_SUBMITTED',
      );
}

/// 实名状态机（§1.3）。
enum RealNameState {
  notSubmitted('NOT_SUBMITTED', '未认证'),
  pending('PENDING', '审核中'),
  approved('APPROVED', '已认证'),
  rejected('REJECTED', '已驳回');

  const RealNameState(this.code, this.label);

  final String code;
  final String label;

  static RealNameState fromCode(String? code) => RealNameState.values.firstWhere(
        (e) => e.code == code,
        orElse: () => RealNameState.notSubmitted,
      );

  /// 是否允许提交/重新提交材料（与后端状态机一致）。
  bool get canSubmit => this == RealNameState.notSubmitted || this == RealNameState.rejected;
}

/// 实名状态详情（§1.3）。
class RealNameStatus {
  const RealNameStatus({
    required this.state,
    this.realNameMasked,
    this.idNumberMasked,
    this.rejectReason,
    this.submittedAt,
    this.reviewedAt,
  });

  final RealNameState state;
  final String? realNameMasked;
  final String? idNumberMasked;
  final String? rejectReason;
  final String? submittedAt;
  final String? reviewedAt;

  factory RealNameStatus.fromJson(Map<String, dynamic> json) => RealNameStatus(
        state: RealNameState.fromCode(json['status'] as String?),
        realNameMasked: json['realNameMasked'] as String?,
        idNumberMasked: json['idNumberMasked'] as String?,
        rejectReason: json['rejectReason'] as String?,
        submittedAt: json['submittedAt'] as String?,
        reviewedAt: json['reviewedAt'] as String?,
      );
}

/// 消息类型（与后端 AppAdminConstants 同集合）。
enum MessageType {
  system('SYSTEM', '系统'),
  review('REVIEW', '审核'),
  transaction('TRANSACTION', '交易'),
  benefit('BENEFIT', '福利');

  const MessageType(this.code, this.label);

  final String code;
  final String label;

  static MessageType? fromCode(String? code) {
    for (final value in MessageType.values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

/// 通知渠道（§1.5）。
enum NotificationChannel {
  inbox('INBOX', '站内消息'),
  push('PUSH', '推送通知');

  const NotificationChannel(this.code, this.label);

  final String code;
  final String label;

  static NotificationChannel fromCode(String? code) => NotificationChannel.values.firstWhere(
        (e) => e.code == code,
        orElse: () => NotificationChannel.inbox,
      );
}

/// 消息列表行（§1.5）。
class MessageItem {
  const MessageItem({
    required this.messageId,
    required this.type,
    required this.title,
    this.summary = '',
    this.content,
    this.read = false,
    this.createdAt,
  });

  final int messageId;
  final String type;
  final String title;
  final String summary;
  final String? content;
  final bool read;
  final String? createdAt;

  MessageType? get typeEnum => MessageType.fromCode(type);
  String get typeLabel => typeEnum?.label ?? type;

  factory MessageItem.fromJson(Map<String, dynamic> json) => MessageItem(
        messageId: (json['messageId'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? 'SYSTEM',
        title: json['title'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        content: json['content'] as String?,
        read: json['read'] as bool? ?? false,
        createdAt: json['createdAt'] as String?,
      );
}

/// 未读数（§1.5）。
class UnreadCount {
  const UnreadCount({required this.total, this.byType = const {}});

  final int total;
  final Map<String, int> byType;

  static const UnreadCount zero = UnreadCount(total: 0);

  factory UnreadCount.fromJson(Map<String, dynamic> json) {
    final raw = json['byType'];
    final byType = <String, int>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is num) byType['$key'] = value.toInt();
      });
    }
    return UnreadCount(total: (json['total'] as num?)?.toInt() ?? 0, byType: byType);
  }
}

/// 通知偏好条目（§1.5）。
class NotificationPreference {
  const NotificationPreference({
    required this.channel,
    required this.type,
    required this.enabled,
  });

  final NotificationChannel channel;
  final MessageType? type;
  final bool enabled;

  String get typeCode => type?.code ?? '';
  String get typeLabel => type?.label ?? typeCode;

  factory NotificationPreference.fromJson(Map<String, dynamic> json) => NotificationPreference(
        channel: NotificationChannel.fromCode(json['channel'] as String?),
        type: MessageType.fromCode(json['type'] as String?),
        enabled: json['enabled'] as bool? ?? true,
      );

  NotificationPreference copyWith({bool? enabled}) => NotificationPreference(
        channel: channel,
        type: type,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'channel': channel.code,
        'type': typeCode,
        'enabled': enabled,
      };
}

/// 反馈状态（与数据库 CHECK 约束同集合）。
enum FeedbackStatus {
  submitted('SUBMITTED', '已提交'),
  processing('PROCESSING', '处理中'),
  replied('REPLIED', '已回复'),
  closed('CLOSED', '已关闭');

  const FeedbackStatus(this.code, this.label);

  final String code;
  final String label;

  static FeedbackStatus fromCode(String? code) => FeedbackStatus.values.firstWhere(
        (e) => e.code == code,
        orElse: () => FeedbackStatus.submitted,
      );
}

/// 反馈分类（与后端白名单同集合）。
enum FeedbackCategory {
  feature('FEATURE', '功能建议'),
  experience('EXPERIENCE', '体验问题'),
  bug('BUG', '缺陷报告'),
  complaint('COMPLAINT', '投诉'),
  other('OTHER', '其他');

  const FeedbackCategory(this.code, this.label);

  final String code;
  final String label;

  static FeedbackCategory fromCode(String? code) => FeedbackCategory.values.firstWhere(
        (e) => e.code == code,
        orElse: () => FeedbackCategory.other,
      );
}

/// 我的反馈（§1.6）。
class FeedbackItem {
  const FeedbackItem({
    required this.feedbackId,
    required this.category,
    required this.content,
    required this.status,
    this.reply,
    this.attachments = const [],
    this.submittedAt,
    this.handledAt,
  });

  final int feedbackId;
  final String category;
  final String content;
  final FeedbackStatus status;
  final String? reply;
  final List<String> attachments;
  final String? submittedAt;
  final String? handledAt;

  FeedbackCategory get categoryEnum => FeedbackCategory.fromCode(category);
  String get categoryLabel => categoryEnum.label;

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    return FeedbackItem(
      feedbackId: (json['feedbackId'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'OTHER',
      content: json['content'] as String? ?? '',
      status: FeedbackStatus.fromCode(json['status'] as String?),
      reply: json['reply'] as String?,
      attachments: rawAttachments is List ? rawAttachments.whereType<String>().toList() : const [],
      submittedAt: json['submittedAt'] as String?,
      handledAt: json['handledAt'] as String?,
    );
  }
}

/// 换绑第 1 步结果（§1.4）。凭证只在内存中使用，不持久化、不打印。
class PhoneStepUp {
  const PhoneStepUp({required this.stepUpToken, required this.expiresIn});

  final String stepUpToken;
  final int expiresIn;

  factory PhoneStepUp.fromJson(Map<String, dynamic> json) => PhoneStepUp(
        stepUpToken: json['stepUpToken'] as String? ?? '',
        expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
      );
}
