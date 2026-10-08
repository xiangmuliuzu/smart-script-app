import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/auth_providers.dart';
import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../models/user.dart';
import '../bookstore/data/bookstore_models.dart';
import '../bookstore/data/content_providers.dart';
import '../bookstore/data/content_repository.dart';
import '../user_center/data/user_center_models.dart';
import '../user_center/data/user_center_providers.dart';
import '../user_center/widgets/user_center_widgets.dart';

/// 我的（对照 H5 原型 `profile.html` / `profile_client.html`）。
///
/// 结构与原型一致：
///   1. 头部卡：头像、昵称、实名标签、简介与「去认证」按钮；
///   2. 快捷宫格：一行四个圆形入口，创作者与甲方角色分流（原型两套入口）；
///   3. 我的书架：一行三本的竖版书封网格。
/// 数据来源：`/auth/me` 的全局身份 + `/messages/unread-count` 未读数 + 书架接口。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    // 该路由受登录守卫保护，正常情况必有会话；兜底空用户避免游客态空指针。
    final user = auth.user ?? const User(userId: 0, userType: UserType.user);
    final unread = ref.watch(unreadCountProvider);
    final shelf = ref.watch(shelfProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      drawer: _ProfileDrawer(user: user, ref: ref),
      body: SafeArea(
        // Builder 使 Scaffold.of 取到本页的 Scaffold；
        // 直接用 build 的 context 会命中外层 HomeShell 的 Scaffold（无抽屉）导致点击无效。
        child: Builder(
          builder: (context) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(unreadCountProvider);
              ref.invalidate(shelfProvider);
              await ref.read(authControllerProvider.notifier).refreshMe();
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _TopBar(onDrawer: () => Scaffold.of(context).openDrawer(), onSwitch: () async {
                  // 切换账号：与退出登录同一动作，回登录页后可换身份登录。
                  AuthGuard.clearOnLogout(ref);
                  await ref.read(authControllerProvider.notifier).logout();
                }),
                _Header(
                  user: user,
                  onAuth: () =>
                      AuthGuard.pushProtected(context, ref, target: RoutePath.realName),
                ),
                _CardBox(
                  child: _QuickGrid(
                    ref: ref,
                    user: user,
                    unread: unread.valueOrNull?.total ?? 0,
                  ),
                ),
                _CardBox(
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

/// 卡片容器：对应原型 `.cardbox`（白底圆角 + 浅阴影，左右 16 上下 12 间距）。
class _CardBox extends StatelessWidget {
  const _CardBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 顶栏：左上抽屉按钮 + 居中标题 + 右侧「切换账号」（对照原型 `.appbar`）。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onDrawer, required this.onSwitch});

  final VoidCallback onDrawer;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text(
            '我的',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text1),
          ),
          Positioned(
            left: 4,
            child: IconButton(
              onPressed: onDrawer,
              icon: const Icon(Icons.menu, size: 22, color: AppColors.text2),
              tooltip: '工具与设置',
            ),
          ),
          Positioned(
            right: 12,
            child: TextButton(
              onPressed: onSwitch,
              child: const Text('切换账号', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧边抽屉：收纳账号安全、通知偏好、意见反馈与退出登录（原型的抽屉入口）。
class _ProfileDrawer extends StatelessWidget {
  const _ProfileDrawer({required this.user, required this.ref});

  final User user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final nickname = (user.nickname == null || user.nickname!.isEmpty) ? '未设置昵称' : user.nickname!;
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  _Avatar(nickname: nickname, avatar: user.avatar),
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
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            _DrawerItem(
              icon: Icons.lock_outline,
              label: '账号安全',
              onTap: () => _push(context, RoutePath.accountSecurity),
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
            const Divider(height: 1, color: AppColors.divider),
            _DrawerItem(
              icon: Icons.logout,
              label: '退出登录',
              danger: true,
              onTap: () async {
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

/// 头部卡：头像 + 昵称/实名标签/简介 + 「去认证」按钮（原型 `.prof-head`）。
class _Header extends StatelessWidget {
  const _Header({required this.user, required this.onAuth});

  final User user;
  final VoidCallback onAuth;

  @override
  Widget build(BuildContext context) {
    final state = RealNameState.fromCode(user.realNameStatus);
    final approved = state == RealNameState.approved;
    final nickname = (user.nickname == null || user.nickname!.isEmpty) ? '未设置昵称' : user.nickname!;

    return _CardBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Avatar(nickname: nickname, avatar: user.avatar),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    UserStatusChip(text: state.label, color: _tagColor(state)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  (user.bio != null && user.bio!.isNotEmpty)
                      ? user.bio!
                      : '${user.userType.label} · 简介待完善',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _AuthButton(approved: approved, onTap: approved ? null : onAuth),
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

/// 圆形头像：优先网络图，缺省显示昵称首字（原型 `.ava`）。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.nickname, this.avatar});

  final String nickname;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 56,
        height: 56,
        child: (avatar != null && avatar!.isNotEmpty)
            ? Image.network(
                avatar!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder,
              )
            : _placeholder,
      ),
    );
  }

  Widget get _placeholder => Container(
        color: AppColors.primaryTint,
        alignment: Alignment.center,
        child: Text(
          nickname.characters.first,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      );
}

/// 「去认证」按钮：已通过实名将变为主色实底并置灰（原型 `.auth-btn`）。
class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.approved, required this.onTap});

  final bool approved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: approved ? AppColors.primary : AppColors.primaryTint,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            approved ? '已认证' : '去认证',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: approved ? Colors.white : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 快捷宫格：一行四个圆形图标入口（原型 `.quick`）。
///
/// 入口按账号类型分流（原型 profile.html 创作者 / profile_client.html 甲方）；
/// 未接入真实页面的入口点击仅提示「建设中」。
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.ref, required this.user, required this.unread});

  final WidgetRef ref;
  final User user;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final entries = <_QuickEntry>[
      _QuickEntry(ref, Icons.star_outline, '收藏',
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.favorites)),
      _QuickEntry(ref, Icons.chat_bubble_outline, '消息',
          badge: unread,
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.messages)),
      _QuickEntry(ref, Icons.history, '浏览历史'),
      _QuickEntry(ref, Icons.edit_outlined, '编辑资料',
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.profileEdit)),
      if (user.isCreator || user.authorCapability) ...[
        _QuickEntry(ref, Icons.description_outlined, '我的剧本'),
        _QuickEntry(ref, Icons.headset_mic_outlined, '询盘管理'),
        _QuickEntry(ref, Icons.account_balance_wallet_outlined, '交易管理'),
        _QuickEntry(ref, Icons.approval, '我的印章'),
        _QuickEntry(ref, Icons.bar_chart, '创作者后台'),
      ],
      if (user.isClient) ...[
        _QuickEntry(ref, Icons.fact_check_outlined, '我的选品'),
        _QuickEntry(ref, Icons.campaign_outlined, '需求发布'),
        _QuickEntry(ref, Icons.account_balance_wallet_outlined, '交易管理'),
        _QuickEntry(ref, Icons.movie_outlined, '短剧管理'),
        _QuickEntry(ref, Icons.approval, '我的印章'),
      ],
      _QuickEntry(ref, Icons.card_giftcard, '福利'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 4;
        final cellWidth = constraints.maxWidth / columns;
        return Wrap(
          children: [
            for (final entry in entries)
              SizedBox(
                width: cellWidth,
                height: 84,
                child: entry,
              ),
          ],
        );
      },
    );
  }
}

class _QuickEntry extends StatelessWidget {
  const _QuickEntry(this.ref, this.icon, this.label, {this.onTap, this.badge = 0});

  final WidgetRef ref;
  final IconData icon;
  final String label;

  /// 入口尚未接入页面时为 null，点击仅提示建设中。
  final void Function(BuildContext context, WidgetRef ref)? onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap != null ? () => onTap!(context, ref) : () => showAppToast(context, '「$label」建设中'),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: AppColors.primary),
                ),
                if (badge > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.all(Radius.circular(9)),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.text2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 我的书架：一行三本的竖版书封网格（原型 `.shelf` / `.book`）。
class _ShelfSection extends StatelessWidget {
  const _ShelfSection({required this.shelf});

  final AsyncValue<ShelfPayload> shelf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我的书架',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text1),
        ),
        const SizedBox(height: 10),
        shelf.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, _) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('书架加载失败，下拉可重试',
                  style: TextStyle(fontSize: 12, color: AppColors.text3)),
            ),
          ),
          data: (payload) {
            if (payload.list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('书架暂无作品，去书城添加吧',
                      style: TextStyle(fontSize: 12, color: AppColors.text3)),
                ),
              );
            }
            return GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: 0.62,
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

/// 竖版书封：3:4 渐变底 + 左侧书脊线 + 书名白字（原型 `.book .cv`）。
class _ShelfBook extends StatelessWidget {
  const _ShelfBook({required this.work, required this.gradientIndex});

  final BookItem work;
  final int gradientIndex;

  // 对照原型 app.css `.book .cv.g1/g2/g3` 的三套蓝色系书封渐变。
  static const _gradients = <List<Color>>[
    <Color>[Color(0xFF2F5FA8), Color(0xFF1B3A6B)],
    <Color>[Color(0xFF254E90), Color(0xFF16305C)],
    <Color>[Color(0xFF4A76B8), Color(0xFF2A4C86)],
  ];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RoutePath.workDetailUrl(work.workId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _gradients[gradientIndex % _gradients.length],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(color: Color(0x12000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Stack(
                children: [
                  const Positioned(
                    left: 7,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child: ColoredBox(color: Colors.white24),
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
            ),
          ),
          const SizedBox(height: 6),
          Text(
            work.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.text1),
          ),
          Text(
            work.authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.text3),
          ),
        ],
      ),
    );
  }
}
