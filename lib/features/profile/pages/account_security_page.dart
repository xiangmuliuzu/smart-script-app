import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 账号安全（规格 §8.5，契约 §1.4）。
///
/// 展示脱敏手机号与实名状态，提供换绑手机号与密码入口：
///   - 已设置密码 -> 修改密码（旧密码 + 新密码）
///   - 未设置密码 -> 首次设置密码
/// 换绑成功后后端吊销全部会话，本页要求用户用新手机号重新登录。
class AccountSecurityPage extends ConsumerWidget {
  const AccountSecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return UserCenterScaffold(
        title: '账号安全',
        actions: null,
        body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is ApiException ? error.message : '加载失败，请稍后重试',
              style: const TextStyle(color: AppColors.text2),
            ),
          ),
        ),
        data: (profile) => _buildBody(context, ref, profile),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, UserProfile profile) {
    final hasPassword = ref.watch(authControllerProvider).user?.hasPassword ?? false;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              _Row(
                label: '手机号',
                value: profile.phoneMasked ?? '-',
                onTap: () => AuthGuard.pushProtected(context, ref, target: RoutePath.phoneChange),
              ),
              _Row(
                label: hasPassword ? '登录密码' : '设置密码',
                value: hasPassword ? '已设置' : '未设置',
                onTap: () => _openPasswordPage(context, ref, hasPassword),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            '换绑手机号后需使用新手机号重新登录；修改密码会使其它设备的登录状态失效。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
      ],
    );
  }

  void _openPasswordPage(BuildContext context, WidgetRef ref, bool hasPassword) {
    // 独立页面而不是底部弹窗：弹窗在软键盘弹出后命中区域错位，
    // 人工冒烟中无法完成提交（点击「确定」会被判为点击遮罩）。
    AuthGuard.pushProtected(
      context,
      ref,
      target: '${RoutePath.passwordEdit}?hasPassword=${hasPassword ? '1' : '0'}',
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.text1))),
            Text(value, style: const TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}
