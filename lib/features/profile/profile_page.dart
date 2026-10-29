import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/auth_providers.dart';
import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/avatar_url.dart';
import '../../core/widgets/app_toast.dart';
import '../../models/user.dart';
import '../bookstore/data/bookstore_models.dart';
import '../bookstore/data/content_providers.dart';
import '../bookstore/data/content_repository.dart';
import '../user_center/data/user_center_models.dart';
import '../user_center/data/user_center_providers.dart';
import '../user_center/data/user_social_models.dart';
import '../user_center/widgets/user_center_widgets.dart';

/// 我的（东方书卷·创作者工作台风格）。
///
/// 视觉层次：
///   1. 沉浸式去卡片化头部：头像、昵称、实名标签、会话入口 + 独立三栏等宽社交统计；
///   2. 创作者/甲方专属 Bento 工作台横幅 + 单行零翻页高频工具栏；
///   3. 仿真立体书封书架：带内描边、装订书脊光泽与左对齐杂志感排版。
/// 数据来源：`/auth/me` 的全局身份 + 公开资料统计 + 书架接口。
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 「我的」是身份信息的主要展示入口：进入时刷新全局身份（/auth/me），
    // 使后台运维端刚通过的实名审核等状态无需重新登录即可显示。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(authControllerProvider.notifier).refreshMe();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台切回前台时刷新身份：审核状态可能在 App 处于后台期间于运维端变更。
    if (state == AppLifecycleState.resumed) {
      ref.read(authControllerProvider.notifier).refreshMe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    // 该路由受登录守卫保护，正常情况必有会话；兜底空用户避免游客态空指针。
    final user = auth.user ?? const User(userId: 0, userType: UserType.user);
    final shelf = ref.watch(shelfProvider);
    // 粉丝/关注/获赞统计来自公开资料接口；加载中或失败时头部显示占位。
    final profileView = ref.watch(userProfileViewProvider(user.userId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      drawer: _ProfileDrawer(user: user, ref: ref),
      body: SafeArea(
        // Builder 使 Scaffold.of 取到本页的 Scaffold；
        // 直接用 build 的 context 会命中外层 HomeShell 的 Scaffold（无抽屉）导致点击无效。
        child: Builder(
          builder: (context) => RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(shelfProvider);
              ref.invalidate(userProfileViewProvider(user.userId));
              await ref.read(authControllerProvider.notifier).refreshMe();
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                _TopBar(
                  onDrawer: () => Scaffold.of(context).openDrawer(),
                  onChat: () => AuthGuard.pushProtected(
                    context,
                    ref,
                    target: RoutePath.chatSessionList,
                  ),
                ),
                _Header(
                  user: user,
                  profileView: profileView,
                  // 点击头像/昵称进入个人主页（0 = 自己）；编辑资料移到个人主页「···」菜单。
                  onEdit: () => AuthGuard.pushProtected(
                    context,
                    ref,
                    target: RoutePath.userProfileUrl(0),
                  ),
                  onAuth: () => AuthGuard.pushProtected(
                    context,
                    ref,
                    target: RoutePath.realName,
                  ),
                  onTapFollowing: () => AuthGuard.pushProtected(
                    context,
                    ref,
                    target: RoutePath.userFollowListUrl(
                      user.userId,
                      following: true,
                    ),
                  ),
                  onTapFollowers: () => AuthGuard.pushProtected(
                    context,
                    ref,
                    target: RoutePath.userFollowListUrl(
                      user.userId,
                      following: false,
                    ),
                  ),
                ),
                if (user.authorCapability)
                  _CreatorBentoSection(ref: ref)
                else if (user.isClient)
                  _ClientBentoSection(ref: ref),
                _CardBox(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  child: _QuickToolRow(
                    ref: ref,
                    isCreator: user.authorCapability,
                  ),
                ),
                _CardBox(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: _ShelfSection(shelf: shelf),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Emil 规范按压反馈组件：
/// 按压时以强 ease-out 曲线微缩放到 `0.97`（130ms），松手回弹（180ms），
/// 并遵守系统无障碍减少动态效果（`disableAnimations`）。
class _ScaleTap extends StatefulWidget {
  const _ScaleTap({
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<_ScaleTap> {
  static const Cubic _easeOutStrong = Cubic(0.23, 1.0, 0.32, 1.0);
  static const double _scaleDown = 0.97;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final targetScale = (_pressed && !reduceMotion) ? _scaleDown : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap != null ? (_) => _setPressed(true) : null,
      onTapUp: widget.onTap != null ? (_) => _setPressed(false) : null,
      onTapCancel: widget.onTap != null ? () => _setPressed(false) : null,
      onTap: widget.onTap != null
          ? () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: targetScale,
        duration: Duration(milliseconds: _pressed ? 120 : 180),
        curve: _easeOutStrong,
        child: widget.child,
      ),
    );
  }
}

/// 卡片容器：白底连续圆角 + 柔和深蓝投影 + 极细高光描边。
class _CardBox extends StatelessWidget {
  const _CardBox({
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: ShapeDecoration(
        color: AppColors.card,
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Colors.white.withOpacity(0.85), width: 1),
        ),
        shadows: const [
          BoxShadow(
            color: Color(0x0C183A6E),
            offset: Offset(0, 6),
            blurRadius: 20,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 顶栏：左侧抽屉菜单按钮和右侧会话入口。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onDrawer, required this.onChat});

  final VoidCallback onDrawer;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ScaleTap(
            onTap: onDrawer,
            child: Tooltip(
              message: '工具与设置',
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.95),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.notes_rounded,
                  size: 21,
                  color: AppColors.text1,
                ),
              ),
            ),
          ),
          _ScaleTap(
            onTap: onChat,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.78),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.95),
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '会话',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧边抽屉：收纳账号安全、实名认证、通知偏好、意见反馈与退出登录。
class _ProfileDrawer extends StatelessWidget {
  const _ProfileDrawer({required this.user, required this.ref});

  final User user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final nickname =
        (user.nickname == null || user.nickname!.isEmpty) ? '未设置用户名称' : user.nickname!;
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            InkWell(
              // 抽屉头部（头像+昵称）：进入个人主页（0 = 自己）。
              onTap: () => _push(context, RoutePath.userProfileUrl(0)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    _Avatar(nickname: nickname, avatar: user.avatar, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.userType.label,
                            style: const TextStyle(fontSize: 12, color: AppColors.text3),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.text3,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            _DrawerItem(
              icon: Icons.lock_outline,
              label: '账号安全',
              onTap: () => _push(context, RoutePath.accountSecurity),
            ),
            _DrawerItem(
              icon: Icons.verified_user_outlined,
              label: '实名认证',
              onTap: () => _push(context, RoutePath.realName),
            ),
            _DrawerItem(
              icon: Icons.tune,
              label: '通知偏好',
              onTap: () => _push(context, RoutePath.notificationPreferences),
            ),
            _DrawerItem(
              icon: Icons.feedback_outlined,
              label: '意见反馈',
              onTap: () => _push(context, RoutePath.feedback),
            ),
            // 申请入口只取决于当前能力，关闭后即使账号类型仍是创作者也可重新申请。
            if (!user.authorCapability)
              _DrawerItem(
                icon: Icons.workspace_premium_outlined,
                label: '成为创作者',
                onTap: () => _push(context, RoutePath.creatorApply),
              ),
            const Divider(height: 1, color: AppColors.divider),
            _DrawerItem(
              icon: Icons.logout,
              label: '退出登录',
              danger: true,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('确认退出'),
                    content: const Text('确定要退出当前账号吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text(
                          '退出',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                Navigator.pop(context);
                // 主动退出：清空回跳意图（规格 §8.1）
                AuthGuard.clearOnLogout(ref);
                await ref.read(authControllerProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, String target) {
    Navigator.pop(context);
    AuthGuard.pushProtected(context, ref, target: target);
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text1;
    return ListTile(
      leading: Icon(icon, size: 20, color: danger ? AppColors.danger : AppColors.text2),
      title: Text(label, style: TextStyle(fontSize: 15, color: color)),
      onTap: onTap,
    );
  }
}

/// 沉浸式头部：去卡片化设计，直接融于顶部浅冰蓝渐变，包含头像、昵称、实名标签与三栏独立统计。
class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.profileView,
    required this.onEdit,
    required this.onAuth,
    required this.onTapFollowing,
    required this.onTapFollowers,
  });

  final User user;

  /// 公开资料统计（粉丝/关注/获赞），加载中或失败时为空。
  final AsyncValue<UserProfileView> profileView;
  final VoidCallback onEdit;
  final VoidCallback onAuth;
  final VoidCallback onTapFollowing;
  final VoidCallback onTapFollowers;

  @override
  Widget build(BuildContext context) {
    final state = RealNameState.fromCode(user.realNameStatus);
    final approved = state == RealNameState.approved;
    final nickname =
        (user.nickname == null || user.nickname!.isEmpty) ? '未设置用户名称' : user.nickname!;
    final roleSubtitle = user.authorCapability
        ? '认证创作者 · 剧本与漫剧工作台'
        : (user.isClient ? '认证甲方 · 剧本选品与合作' : user.userType.label);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ScaleTap(
                onTap: onEdit,
                child: _Avatar(
                  nickname: nickname,
                  avatar: user.avatar,
                  size: 64,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onEdit,
                            child: Text(
                              nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: AppColors.text1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        UserStatusChip(text: state.label, color: _tagColor(state)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      roleSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              if (!approved) ...[
                const SizedBox(width: 8),
                _AuthButton(onTap: onAuth),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _StatsBar(
            view: profileView,
            onTapFollowing: onTapFollowing,
            onTapFollowers: onTapFollowers,
            onTapLikes: onEdit,
          ),
        ],
      ),
    );
  }

  Color _tagColor(RealNameState state) {
    switch (state) {
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

/// 独立三栏社交资产栏：关注 / 粉丝 / 获赞。
/// 采用 Tabular Figures 等宽数字排版，防止异步加载回填时产生水平抖动。
class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.view,
    required this.onTapFollowing,
    required this.onTapFollowers,
    required this.onTapLikes,
  });

  final AsyncValue<UserProfileView> view;
  final VoidCallback onTapFollowing;
  final VoidCallback onTapFollowers;
  final VoidCallback onTapLikes;

  @override
  Widget build(BuildContext context) {
    final profile = view.valueOrNull;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: ShapeDecoration(
        color: Colors.white.withOpacity(0.68),
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withOpacity(0.9), width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _StatMetricItem(
                label: '关注',
                value: profile?.followingCount,
                onTap: onTapFollowing,
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              indent: 6,
              endIndent: 6,
              color: AppColors.primary.withOpacity(0.10),
            ),
            Expanded(
              child: _StatMetricItem(
                label: '粉丝',
                value: profile?.followerCount,
                onTap: onTapFollowers,
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              indent: 6,
              endIndent: 6,
              color: AppColors.primary.withOpacity(0.10),
            ),
            Expanded(
              child: _StatMetricItem(
                label: '获赞',
                value: profile?.likeCount,
                onTap: onTapLikes,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatMetricItem extends StatelessWidget {
  const _StatMetricItem({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final int? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ScaleTap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value == null ? '-' : _compact(value!),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text1,
                fontFeatures: [FontFeature.tabularFigures()],
                height: 1.15,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 大数字压缩为「1.2万」，与列表页计数展示保持一致。
  static String _compact(int value) {
    if (value < 10000) return '$value';
    final wan = value / 10000;
    return '${wan.toStringAsFixed(wan >= 100 ? 0 : 1)}万';
  }
}

/// 圆形头像：带纯白外环与柔和立体阴影，缺省显示渐变底色 + 昵称首字。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.nickname, this.avatar, this.size = 56});

  final String nickname;
  final String? avatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A183A6E),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipOval(
        child: (avatar != null && avatar!.isNotEmpty)
            ? Image.network(
                avatarUrl(avatar),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder,
              )
            : _placeholder,
      ),
    );
  }

  Widget get _placeholder => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFDCE9FA), Color(0xFFC2D8F6)],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          nickname.characters.first,
          style: TextStyle(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      );
}

/// 「去认证」按钮：仅在实名未通过时展示（通过后由昵称旁的标签表达状态）。
class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26254E90),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '去认证',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 15, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// 创作者专属 Bento 工作台区：
/// 左侧主卡突出「AI 创作」，右侧上下叠放「我的作品」「询盘管理」与「订单管理」，
/// 将核心生产力工具从普通宫格中提权，同时解放下方工具栏实现零翻页。
class _CreatorBentoSection extends StatelessWidget {
  const _CreatorBentoSection({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        height: 176,
        child: Row(
          children: [
            // 左主卡：AI 创作
            Expanded(
              flex: 11,
              child: _ScaleTap(
                onTap: () => AuthGuard.pushProtected(
                  context,
                  ref,
                  target: RoutePath.aiCenter,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  decoration: ShapeDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2B59A2), Color(0xFF1A3868)],
                    ),
                    shape: ContinuousRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    shadows: const [
                      BoxShadow(
                        color: Color(0x281D3E73),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        right: -6,
                        bottom: -8,
                        child: Icon(
                          Icons.auto_awesome,
                          size: 64,
                          color: Colors.white.withOpacity(0.10),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color: Color(0xFFFFE082),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'AI 创作',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '灵感大纲 · 智能续写润色',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.82),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '进入工作台',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 右侧三横卡：我的作品 + 询盘管理 + 订单管理
            Expanded(
              flex: 10,
              child: Column(
                children: [
                  // 我的作品（原底部「创作」tab 的根页面，现收进「我的」Bento 工作台）
                  Expanded(
                    child: _BentoSubCard(
                      icon: Icons.library_books_outlined,
                      iconColor: AppColors.primary,
                      iconBg: AppColors.primaryTint,
                      title: '我的作品',
                      subtitle: '作品管理与创作',
                      onTap: () => AuthGuard.pushProtected(
                        context,
                        ref,
                        target: RoutePath.create,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _BentoSubCard(
                      icon: Icons.headset_mic_outlined,
                      iconColor: const Color(0xFF1F6E5A),
                      iconBg: const Color(0xFFE6F4F0),
                      title: '询盘管理',
                      subtitle: '查看与处理询盘',
                      onTap: () => AuthGuard.pushProtected(
                        context,
                        ref,
                        target: RoutePath.inquiryList,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _BentoSubCard(
                      icon: Icons.shopping_bag_outlined,
                      iconColor: const Color(0xFFB76E1D),
                      iconBg: const Color(0xFFFCF3E6),
                      title: '订单管理',
                      subtitle: '查看订单与合同',
                      onTap: () => AuthGuard.pushProtected(
                        context,
                        ref,
                        target: RoutePath.orderList,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 甲方专属 Bento 区：展示我的选品、需求发布、短剧管理、我的印章。
class _ClientBentoSection extends StatelessWidget {
  const _ClientBentoSection({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _BentoSubCard(
                  icon: Icons.fact_check_outlined,
                  iconColor: AppColors.primary,
                  iconBg: AppColors.primaryTint,
                  title: '我的选品',
                  subtitle: '意向剧本清单',
                  onTap: () => showAppToast(context, '「我的选品」建设中'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BentoSubCard(
                  icon: Icons.campaign_outlined,
                  iconColor: const Color(0xFFC96A1B),
                  iconBg: const Color(0xFFFEF3E8),
                  title: '需求发布',
                  subtitle: '征稿与定制需求',
                  onTap: () => showAppToast(context, '「需求发布」建设中'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _BentoSubCard(
                  icon: Icons.movie_outlined,
                  iconColor: const Color(0xFF534696),
                  iconBg: const Color(0xFFF1EFFB),
                  title: '短剧管理',
                  subtitle: '制作与上线跟进',
                  onTap: () => showAppToast(context, '「短剧管理」建设中'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BentoSubCard(
                  icon: Icons.approval_outlined,
                  iconColor: const Color(0xFF1F6E5A),
                  iconBg: const Color(0xFFE6F4F0),
                  title: '我的印章',
                  subtitle: '电子签章管理',
                  onTap: () => AuthGuard.pushProtected(
                    context,
                    ref,
                    target: RoutePath.mySeal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BentoSubCard extends StatelessWidget {
  const _BentoSubCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: ShapeDecoration(
          color: AppColors.card,
          shape: ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.white.withOpacity(0.9), width: 1),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x0A183A6E),
              offset: Offset(0, 4),
              blurRadius: 14,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: ShapeDecoration(
                color: iconBg,
                shape: ContinuousRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.text3,
            ),
          ],
        ),
      ),
    );
  }
}

/// 常用工具单行直达：5 个高频入口一行排开，采用语义淡彩圆角矩形图标，零翻页隐藏。
class _QuickToolRow extends StatelessWidget {
  const _QuickToolRow({required this.ref, required this.isCreator});

  final WidgetRef ref;
  final bool isCreator;

  @override
  Widget build(BuildContext context) {
    final tools = <_QuickToolItem>[
      _QuickToolItem(
        icon: Icons.star_outline_rounded,
        label: '收藏',
        iconColor: const Color(0xFFD48806),
        bgColor: const Color(0xFFFDF6EC),
        onTap: () => AuthGuard.pushProtected(
          context,
          ref,
          target: RoutePath.favorites,
        ),
      ),
      _QuickToolItem(
        icon: isCreator ? Icons.copyright_outlined : Icons.headset_mic_outlined,
        label: isCreator ? '版权管理' : '询盘管理',
        iconColor: AppColors.primary,
        bgColor: AppColors.primaryTint,
        onTap: () => AuthGuard.pushProtected(
          context,
          ref,
          target: isCreator ? RoutePath.copyrightHome : RoutePath.inquiryList,
        ),
      ),
      _QuickToolItem(
        icon: isCreator ? Icons.approval_outlined : Icons.shopping_bag_outlined,
        label: isCreator ? '我的印章' : '订单管理',
        iconColor: const Color(0xFF1F7A6E),
        bgColor: const Color(0xFFE7F6F4),
        onTap: () => AuthGuard.pushProtected(
          context,
          ref,
          target: isCreator ? RoutePath.mySeal : RoutePath.orderList,
        ),
      ),
      _QuickToolItem(
        icon: Icons.monetization_on_outlined,
        label: '作者收益',
        iconColor: const Color(0xFF4C4B99),
        bgColor: const Color(0xFFF1F0FC),
        onTap: () => AuthGuard.pushProtected(
          context,
          ref,
          target: RoutePath.myIncomeOverview,
        ),
      ),
      _QuickToolItem(
        icon: Icons.card_giftcard_rounded,
        label: '福利',
        iconColor: const Color(0xFFD54941),
        bgColor: const Color(0xFFFEF0EE),
        onTap: () => AuthGuard.pushProtected(
          context,
          ref,
          target: RoutePath.welfareCenter,
        ),
      ),
    ];

    return Row(
      children: [
        for (final item in tools) Expanded(child: item),
      ],
    );
  }
}

class _QuickToolItem extends StatelessWidget {
  const _QuickToolItem({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ScaleTap(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: ShapeDecoration(
              color: bgColor,
              shape: ContinuousRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 我的书架：一行三本的竖版仿真书封网格。
class _ShelfSection extends StatelessWidget {
  const _ShelfSection({required this.shelf});

  final AsyncValue<ShelfPayload> shelf;

  @override
  Widget build(BuildContext context) {
    final count = shelf.valueOrNull?.list.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3.5,
              height: 15,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '我的书架',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text1,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count 本',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
            const Spacer(),
            _ScaleTap(
              onTap: () => context.go(RoutePath.bookstore),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '去书城',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text3,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.text3,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        shelf.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, _) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                '书架加载失败，下拉可重试',
                style: TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ),
          ),
          data: (payload) {
            if (payload.list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_stories_outlined,
                        size: 38,
                        color: AppColors.text3.withOpacity(0.55),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '书架暂无作品，去首页添加吧',
                        style: TextStyle(fontSize: 12, color: AppColors.text3),
                      ),
                    ],
                  ),
                ),
              );
            }
            return GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 14,
              childAspectRatio: 0.58,
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < payload.list.length; i++)
                  _ShelfBook(work: payload.list[i], gradientIndex: i),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 竖版立体书封：优先展示真实封面图，缺失/加载失败时回退到 3:4 书卷渐变底 + 书名。
/// 叠加仿真书脊折痕高光与 1px 内描边，避免纯白/纯黑封面与背景粘连。
class _ShelfBook extends StatelessWidget {
  const _ShelfBook({required this.work, required this.gradientIndex});

  final BookItem work;
  final int gradientIndex;

  // 东方书卷三套深邃兜底书封渐变（黛蓝 / 绛紫 / 苍青）。
  static const _gradients = <List<Color>>[
    <Color>[Color(0xFF2F5FA8), Color(0xFF193560)],
    <Color>[Color(0xFF42366E), Color(0xFF241C42)],
    <Color>[Color(0xFF285963), Color(0xFF16353B)],
  ];

  @override
  Widget build(BuildContext context) {
    return _ScaleTap(
      onTap: () => context.push(RoutePath.workDetailUrl(work.workId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16183A6E),
                    offset: Offset(0, 5),
                    blurRadius: 12,
                  ),
                  BoxShadow(
                    color: Color(0x0A000000),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    work.cover.isEmpty ? _fallback() : _coverImage(),
                    // 仿真左侧书脊明暗折痕光泽
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 8,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black.withOpacity(0.18),
                                Colors.white.withOpacity(0.22),
                                Colors.black.withOpacity(0.06),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.35, 0.7, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 1px 内描边：解决浅白封面或纯黑封面与背景糊化的问题
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: Colors.black.withOpacity(0.08),
                              width: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            work.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            work.authorName.isEmpty ? '佚名' : work.authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.text3,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// 真实封面图：与详情页/书城同一份 cover 数据、同一套 [AppConfig.resolveAssetUrl] 归一，
  /// 撑满网格并裁切；加载失败回退到渐变书封。
  Widget _coverImage() => Image.network(
        AppConfig.resolveAssetUrl(work.cover),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _fallback(),
      );

  /// 封面缺失/加载失败时的兜底书封：深邃书卷渐变 + 书脊装订线 + 书名白字。
  Widget _fallback() => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradients[gradientIndex % _gradients.length],
          ),
        ),
        child: Stack(
          children: [
            if (work.genreName.isNotEmpty)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    work.genreName,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            Center(
              child: Text(
                work.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}
