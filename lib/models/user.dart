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
  });

  final int userId;
  final UserType userType;
  final String? phoneMasked;
  final String? nickname;
  final String? avatar;
  final String realNameStatus;
  final List<String> roles;

  bool get isCreator => userType == UserType.creator;
  bool get isClient => userType == UserType.client;

  factory User.fromJson(Map<String, dynamic> json) => User(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        userType: UserType.fromCode(json['userType'] as String?),
        phoneMasked: json['phoneMasked'] as String?,
        nickname: json['nickname'] as String?,
        avatar: json['avatar'] as String?,
        realNameStatus: json['realNameStatus'] as String? ?? 'NOT_SUBMITTED',
        roles: (json['roles'] as List?)?.whereType<String>().toList() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userType': userType.code,
        'phoneMasked': phoneMasked,
        'nickname': nickname,
        'avatar': avatar,
        'realNameStatus': realNameStatus,
        'roles': roles,
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
