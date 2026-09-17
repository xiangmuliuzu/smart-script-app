/// 账号类型（接口文档 2.1.3 / 数据库 sys_user.user_type）。
enum UserType {
  user('user', '普通用户'),
  creator('creator', '创作者'),
  client('client', '甲方'),
  admin('admin', '管理员');

  const UserType(this.code, this.label);

  final String code;
  final String label;

  static UserType fromCode(String? code) => UserType.values.firstWhere(
        (e) => e.code == code,
        orElse: () => UserType.user,
      );
}

/// 用户核心模型（对照数据库 sys_user 与接口 2.1.3 / 2.2.1 输出字段）。
///
/// 这是框架层提供的**基础模型**，各业务模块可在此之上扩展自己的 DTO。
class User {
  const User({
    required this.userId,
    required this.userType,
    this.phone,
    this.nickname,
    this.avatar,
    this.bio,
    this.status,
    this.authStatus,
  });

  final int userId;
  final UserType userType;
  final String? phone;
  final String? nickname;
  final String? avatar;
  final String? bio;

  /// 账号状态：0 禁用 / 1 正常 / 2 冻结。
  final int? status;

  /// 实名认证状态：none/pending/approved/rejected（接口 2.2.1）。
  final String? authStatus;

  bool get isCreator => userType == UserType.creator;
  bool get isClient => userType == UserType.client;

  factory User.fromJson(Map<String, dynamic> json) => User(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        userType: UserType.fromCode(json['userType'] as String?),
        phone: json['phone'] as String?,
        nickname: json['nickname'] as String?,
        avatar: json['avatar'] as String?,
        bio: json['bio'] as String?,
        status: (json['status'] as num?)?.toInt(),
        authStatus: json['authStatus'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userType': userType.code,
        'phone': phone,
        'nickname': nickname,
        'avatar': avatar,
        'bio': bio,
        'status': status,
        'authStatus': authStatus,
      };
}
