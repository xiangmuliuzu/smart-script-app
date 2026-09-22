/// A3 CurrentUser / AuthSession models (A3-AUTH-CONTRACT-v1).
enum UserType {
  user('01', '普通用户'),
  creator('02', '创作者'),
  client('03', '甲方');

  const UserType(this.code, this.label);

  final String code;
  final String label;

  static UserType fromCode(String? code) => UserType.values.firstWhere(
        (e) => e.code == code,
        orElse: () => UserType.user,
      );
}

class User {
  const User({
    required this.userId,
    required this.userType,
    this.phoneMasked,
    this.nickname,
    this.avatar,
    this.realNameStatus = 'NOT_SUBMITTED',
    this.roles = const [],
    this.hasPassword = false,
  });

  final int userId;
  final UserType userType;
  final String? phoneMasked;
  final String? nickname;
  final String? avatar;
  final String realNameStatus;
  final List<String> roles;

  /// 是否已设置密码（A5）：账号安全页据此在「首次设置密码」与「修改密码」间选择入口。
  final bool hasPassword;

  bool get isCreator => userType == UserType.creator;
  bool get isClient => userType == UserType.client;

  /// 规格 §10 的统一身份能力：实名是否已通过。
  bool get isRealNameApproved => realNameStatus == 'APPROVED';

  /// 规格 §10 的统一身份能力：是否具备某角色。
  bool hasRole(String roleCode) => roles.contains(roleCode);

  factory User.fromJson(Map<String, dynamic> json) => User(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        userType: UserType.fromCode(json['userType'] as String?),
        phoneMasked: json['phoneMasked'] as String?,
        nickname: json['nickname'] as String?,
        avatar: json['avatar'] as String?,
        realNameStatus: json['realNameStatus'] as String? ?? 'NOT_SUBMITTED',
        roles: (json['roles'] as List?)?.whereType<String>().toList() ?? const [],
        hasPassword: json['hasPassword'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userType': userType.code,
        'phoneMasked': phoneMasked,
        'nickname': nickname,
        'avatar': avatar,
        'realNameStatus': realNameStatus,
        'roles': roles,
        'hasPassword': hasPassword,
      };
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshExpiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final int refreshExpiresIn;
  final User user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String? ?? '',
        refreshToken: json['refreshToken'] as String? ?? '',
        tokenType: json['tokenType'] as String? ?? 'Bearer',
        expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
        refreshExpiresIn: (json['refreshExpiresIn'] as num?)?.toInt() ?? 0,
        user: User.fromJson(Map<String, dynamic>.from(json['user'] as Map? ?? {})),
      );
}
