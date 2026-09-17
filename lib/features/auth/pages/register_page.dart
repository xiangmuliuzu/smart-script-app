import 'package:flutter/material.dart';

import '../../../shared/widgets/placeholder_page.dart';

/// 注册页（接口文档 2.1.2）——占位，待登录注册负责人实现。
///
/// 参考 [LoginPage] 的写法：选择账号类型 creator/client、发送验证码、
/// 调用 `ApiEndpoints.register` 即可。
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: '注册',
      subtitle: '账号类型选择 / 短信验证码 / 密码设置',
    );
  }
}
