import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import 'auth_guard.dart';
import 'route_paths.dart';

/// 实名准入守卫（规格 §10）。
///
/// 使用边界（重要）：
///   - 只在业务**确实要求实名**时使用（如可下载素材、签约、提现等准入场景）；
///   - 实名与授权是两件事：角色/权限用 `User.hasRole` / `User.hasPermission` 判断，
///     实名状态只用于业务准入，二者不得互相推导；
///   - 不要用它替代 [AuthGuard.requireLogin]：未登录时本守卫会先转交登录守卫。
///
/// 行为：
///   1. 未登录 -> 先走 [AuthGuard.requireLogin]（保存回跳意图并进登录页），返回 false；
///   2. 已登录但实名未通过 -> 提示并跳转实名认证页，返回 false；
///   3. 已通过 -> 返回 true，调用方继续业务逻辑。
class RealNameGuard {
  RealNameGuard._();

  /// 业务入口调用：返回 true 表示可以继续，false 表示已中断（登录或实名引导）。
  ///
  /// [reason] 用于告知用户为什么需要实名（例如「下载素材需要先完成实名认证」）。
  static Future<bool> requireApproved(
    BuildContext context,
    WidgetRef ref, {
    required String reason,
    required String target,
  }) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) {
      // 未登录：交给统一登录守卫，登录成功后会回到 target
      AuthGuard.requireLogin(context, ref, target: target);
      return false;
    }
    if (user.isRealNameApproved) return true;

    // 已登录但未通过实名：先提示，再由用户确认进入实名认证
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要实名认证'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('暂不'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('去认证'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (!context.mounted) return false;
    AuthGuard.pushProtected(context, ref, target: RoutePath.realName);
    return false;
  }
}
