import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_providers.dart';
import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../user_center/data/user_center_models.dart';
import '../user_center/data/user_center_providers.dart';
import '../user_center/widgets/user_center_widgets.dart';

/// 我的（规格 §8.2）。
///
/// 展示头像、昵称、脱敏手机号、实名认证状态与未读消息数，并提供
/// 个人资料、实名认证、账号安全、消息中心、通知偏好、意见反馈与退出登录入口。
/// 数据来源：`/auth/me` 的全局身份 + `/messages/unread-count` 未读数。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(unreadCountProvider);
            await ref.read(authControllerProvider.notifier).refreshMe();
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Header(
                nickname: user?.nickname,
                avatar: user?.avatar,
                phoneMasked: user?.phoneMasked,
                userTypeLabel: user?.userType.label,
              ),
              const SizedBox(height: 12),
              UserCard(
                children: [
                  UserEntryRow(
                    icon: Icons.person_outline,
                    label: '个人资料',
                    onTap: () => AuthGuard.pushProtected(context, ref, target: RoutePath.profileEdit),
                  ),
                  UserEntryRow(
                    icon: Icons.verified_user_outlined,
                    label: '实名认证',
                    trailingText: RealNameState.fromCode(user?.realNameStatus).label,
                    trailingColor: _realNameColor(user?.realNameStatus),
                    onTap: () => AuthGuard.pushProtected(context, ref, target: RoutePath.realName),
                  ),
                  UserEntryRow(
                    icon: Icons.lock_outline,
                    label: '账号安全',
                    onTap: () => AuthGuard.pushProtected(context, ref, target: RoutePath.accountSecurity),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              UserCard(
                children: [
                  UserEntryRow(
                    icon: Icons.notifications_none,
                    label: '消息中心',
                    badge: unread.valueOrNull?.total ?? 0,
                    onTap: () => AuthGuard.pushProtected(context, ref, target: RoutePath.messages),
                  ),
                  UserEntryRow(
                    icon: Icons.tune,
                    label: '通知偏好',
                    onTap: () => AuthGuard.pushProtected(context, ref, target: RoutePath.notificationPreferences),
                  ),
                  UserEntryRow(
                    icon: Icons.feedback_outlined,
                    label: '意见反馈',
                    onTap: () => AuthGuard.pushProtected(context, ref, target: RoutePath.feedback),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton(
                  onPressed: () async {
                    // 主动退出：清空回跳意图（规格 §8.1）
                    AuthGuard.clearOnLogout(ref);
                    await ref.read(authControllerProvider.notifier).logout();
                  },
                  child: const Text('退出登录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _realNameColor(String? status) {
    switch (RealNameState.fromCode(status)) {
      case RealNameState.approved:
        return AppColors.success;
      case RealNameState.pending:
        return AppColors.warning;
      case RealNameState.rejected:
        return AppColors.danger;
      case RealNameState.notSubmitted:
        return AppColors.text3;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    this.nickname,
    this.avatar,
    this.phoneMasked,
    this.userTypeLabel,
  });

  final String? nickname;
  final String? avatar;
  final String? phoneMasked;
  final String? userTypeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: avatar != null && avatar!.isNotEmpty
                  ? Image.network(
                      avatar!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _AvatarPlaceholder(),
                    )
                  : const _AvatarPlaceholder(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (nickname == null || nickname!.isEmpty) ? '未设置昵称' : nickname!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  phoneMasked ?? '手机号未获取',
                  style: const TextStyle(color: AppColors.text3, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '账号类型：${userTypeLabel ?? '-'}',
                  style: const TextStyle(color: AppColors.text3, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.fill,
      child: const Icon(Icons.account_circle, size: 40, color: AppColors.text3),
    );
  }
}
