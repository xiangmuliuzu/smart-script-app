import '../../../core/config/app_config.dart';

/// 个人主页所用数据模型（§1.7）。
///
/// 覆盖：用户公开资料 + 关注/粉丝/获赞统计 + 关注关系；关注/粉丝列表项。

/// 用户公开资料（个人主页头部）。
class UserProfileView {
  const UserProfileView({
    required this.userId,
    this.nickname = '',
    this.avatar,
    this.bio,
    this.userType = '01',
    this.registeredAt,
    this.followingCount = 0,
    this.followerCount = 0,
    this.likeCount = 0,
    this.isFollowing = false,
    this.isSelf = false,
  });

  final int userId;
  final String nickname;
  final String? avatar;
  final String? bio;

  /// 账号类型原始代码：01 普通用户 / 02 创作者 / 03 甲方。
  final String userType;
  final String? registeredAt;

  final int followingCount;
  final int followerCount;
  final int likeCount;

  /// 当前登录用户是否已关注该用户。
  final bool isFollowing;

  /// 被查看的是否就是当前登录用户本人。
  final bool isSelf;

  /// 是否创作者（影响标签展示）。
  bool get isCreator => userType == '02';

  factory UserProfileView.fromJson(Map<String, dynamic> json) => UserProfileView(
        userId: _int(json['userId']),
        nickname: _text(json['nickname']),
        avatar: _nullableText(json['avatar']),
        bio: _nullableText(json['bio']),
        userType: _text(json['userType'], '01'),
        registeredAt: json['registeredAt'] as String?,
        followingCount: _int(json['followingCount']),
        followerCount: _int(json['followerCount']),
        likeCount: _int(json['likeCount']),
        isFollowing: json['isFollowing'] as bool? ?? false,
        isSelf: json['isSelf'] as bool? ?? false,
      );

  UserProfileView copyWith({
    int? followingCount,
    int? followerCount,
    int? likeCount,
    bool? isFollowing,
  }) =>
      UserProfileView(
        userId: userId,
        nickname: nickname,
        avatar: avatar,
        bio: bio,
        userType: userType,
        registeredAt: registeredAt,
        followingCount: followingCount ?? this.followingCount,
        followerCount: followerCount ?? this.followerCount,
        likeCount: likeCount ?? this.likeCount,
        isFollowing: isFollowing ?? this.isFollowing,
        isSelf: isSelf,
      );
}

/// 用户摘要（关注 / 粉丝列表项）。
class UserSummary {
  const UserSummary({
    required this.userId,
    this.nickname = '',
    this.avatar,
    this.bio,
    this.userType = '01',
    this.isFollowing = false,
  });

  final int userId;
  final String nickname;
  final String? avatar;
  final String? bio;
  final String userType;
  final bool isFollowing;

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
        userId: _int(json['userId']),
        nickname: _text(json['nickname']),
        avatar: _nullableText(json['avatar']),
        bio: _nullableText(json['bio']),
        userType: _text(json['userType'], '01'),
        isFollowing: json['isFollowing'] as bool? ?? false,
      );
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

String _text(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  final s = '$value';
  return s.isEmpty ? fallback : s;
}

String? _nullableText(Object? value) {
  if (value == null) return null;
  final s = '$value'.trim();
  return s.isEmpty ? null : s;
}

/// 头像地址归一化（与全局 avatarUrl 同源，避免循环依赖直接在模型内联）。
String normalizeAvatar(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  return AppConfig.resolveAssetUrl(raw);
}
