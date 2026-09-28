import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/providers/auth_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// 应用根组件。使用 go_router 作为路由来源，主题全局统一。
///
/// 返回键不需要在这里处理：用户中心子页面通过 [AuthGuard.pushProtected] 以
/// `push` 打开，历史栈中有上一页，系统返回键与 AppBar 返回箭头都能自然回退。
///
/// 会话失效（如账号被禁用）的全局提示也挂在这里：无论用户当前停在哪个页面，
/// 只要 [AuthController] 给出了提示文案，就用根 ScaffoldMessenger 弹出一次。
class ScriptApp extends ConsumerStatefulWidget {
  const ScriptApp({super.key});

  @override
  ConsumerState<ScriptApp> createState() => _ScriptAppState();
}

class _ScriptAppState extends ConsumerState<ScriptApp> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final message = next.errorMessage;
      if (message == null || message == previous?.errorMessage) return;
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(milliseconds: 1800),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 48),
          ),
        );
      // 消费一次，避免同一提示被后续 rebuild 重复弹出
      ref.read(authControllerProvider.notifier).consumeErrorMessage();
    });

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scaffoldMessengerKey: _messengerKey,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
