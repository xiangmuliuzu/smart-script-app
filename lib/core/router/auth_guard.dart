import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_providers.dart';
import 'route_intent.dart';
import 'route_paths.dart';

/// A5 统一登录守卫（规格 §8.1）。
///
/// 唯一职责边界：
///   - 页面**不得**自行判断 Token 字符串，也不得自行构造登录页跳转；
///     需要登录的入口一律调用 [requireLogin]。
///   - 未登录时保存结构化 [RouteIntent]，进入登录页；
///   - 登录成功后由登录页消费一次意图并回跳（见 [consumeAndResolve]）。
///
/// 「会话恢复中」（[AuthStatus.unknown]）不视为未登录：此时用户可能已登录，
/// 只是 /auth/me 尚未返回；跳登录页会造成已登录用户被误踢，因此交给启动页等待。
class AuthGuard {
  AuthGuard._();

  /// 是否为已登录状态。
  static bool isLoggedIn(WidgetRef ref) =>
      ref.read(authControllerProvider).status == AuthStatus.authenticated;

  /// 需要登录的入口统一调用：已登录返回 true 由页面继续；未登录保存意图并跳登录页。
  ///
  /// [target] 传当前页面的定位串（含查询参数），用于登录成功后原样回跳。
  static bool requireLogin(
    BuildContext context,
    WidgetRef ref, {
    required String target,
  }) {
    if (isLoggedIn(ref)) return true;
    final store = ref.read(routeIntentStoreProvider);
    if (!ProtectedRoutes.canResume(target)) {
      // 敏感提交页（换绑、账号安全）不参与自动回跳
      store.clear();
    } else {
      final intent = RouteIntent.fromParam(Uri.encodeComponent(target));
      if (intent != null) store.save(intent);
    }
    _goLogin(context, ref);
    return false;
  }

  /// 打开受保护的应用内页面。
  ///
  /// 用 `push` 而不是 `go`：用户中心的子页面需要真实的历史栈，
  /// 这样 AppBar 返回箭头与系统返回键都能自然回到上一页。
  /// 用 `go` 打开根级页面会让历史栈只剩当前一条，按返回键会直接退出应用。
  ///
  /// 已登录：直接 push；未登录：保存意图后去登录页，登录成功再由
  /// [consumeAndResolve] 交回目标并跳转。
  static void pushProtected(BuildContext context, WidgetRef ref, {required String target}) {
    if (requireLogin(context, ref, target: target)) {
      context.push(target);
    }
  }

  /// 消费回跳意图并给出最终目标，供登录页在登录成功后调用。
  ///
  /// 无意图、意图非法或目标不允许恢复时返回 null，由调用方走安全默认首页。
  /// 返回的定位串由调用方 push：用户中心子页面需要真实历史栈，
  /// 这样登录回跳后按返回键能回到上一页而不是退出应用。
  static String? consumeAndResolve(WidgetRef ref) {
    final intent = ref.read(routeIntentStoreProvider).consume();
    if (intent == null) return null;
    if (!ProtectedRoutes.canResume(intent.target)) return null;
    return intent.target;
  }

  /// 主动退出登录：清空回跳意图（规格 §8.1）。
  static void clearOnLogout(WidgetRef ref) {
    ref.read(routeIntentStoreProvider).clear();
  }

  static void _goLogin(BuildContext context, WidgetRef ref) {
    final intent = ref.read(routeIntentStoreProvider).pending;
    final target = intent?.encoded;
    context.go(
      target == null
          ? RoutePath.login
          : '${RoutePath.login}?${RouteIntent.paramName}=$target',
    );
  }
}
