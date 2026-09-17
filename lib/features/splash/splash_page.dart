import 'package:flutter/material.dart';

import '../../shared/widgets/common_views.dart';

/// 启动页：仅用于会话恢复期间的过渡，redirect 会自动跳到登录或首页。
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoadingView(message: '加载中…'));
  }
}
