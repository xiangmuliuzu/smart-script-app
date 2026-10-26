import 'package:flutter/material.dart';
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

/// 我的（对照 H5 原型 `profile.html` / `profile_client.html`）。
///
/// 结构与原型一致：
///   1. 头部卡：头像、昵称、实名标签、简介与「去认证」按钮；
///   2. 快捷宫格：一行四个圆形入口，创作者与甲方角色分流（原型两套入口）；
///   3. 我的书架：一行三本的竖版书封网格。
/// 数据来源：`/auth/me` 的全局身份 + `/messages/unread-count` 未读数 + 书架接口。
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
    final unread = ref.watch(unreadCountProvider);
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
            onRefresh: () async {
              ref.invalidate(unreadCountProvider);
              ref.invalidate(shelfProvider);
              ref.invalidate(userProfileViewProvider(user.userId));
              await ref.read(authControllerProvider.notifier).refreshMe();
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _TopBar(onDrawer: () => Scaffold.of(context).openDrawer()),
                _Header(
                  user: user,
                  profileView: profileView,
                  // 点击头像/昵称进入个人主页（0 = 自己）；编辑资料移到个人主页「···」菜单。
                  onEdit: () =>
                      AuthGuard.pushProtected(context, ref, target: RoutePath.userProfileUrl(0)),
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
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}

/// 顶栏：左上抽屉按钮 + 居中标题（切换账号/退出登录已统一收进抽屉）。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onDrawer});

  final VoidCallback onDrawer;

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
    final nickname = (user.nickname == null || user.nickname!.isEmpty) ? '未设置用户名称' : user.nickname!;
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
                        child: const Text('退出', style: TextStyle(color: AppColors.danger)),
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

/// 头部卡：头像 + 昵称/实名标签/简介 + 「去认证」按钮（原型 `.prof-head`）。
class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.profileView,
    required this.onEdit,
    required this.onAuth,
  });

  final User user;

  /// 公开资料统计（粉丝/关注/获赞），加载中或失败时为空。
  final AsyncValue<UserProfileView> profileView;
  final VoidCallback onEdit;
  final VoidCallback onAuth;

  @override
  Widget build(BuildContext context) {
    final state = RealNameState.fromCode(user.realNameStatus);
    final approved = state == RealNameState.approved;
    final nickname = (user.nickname == null || user.nickname!.isEmpty) ? '未设置用户名称' : user.nickname!;

    return _CardBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: _Avatar(nickname: nickname, avatar: user.avatar),
          ),
          const SizedBox(width: 12),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    UserStatusChip(text: state.label, color: _tagColor(state)),
                  ],
                ),
                const SizedBox(height: 6),
                // 昵称下方改为展示关注/粉丝/获赞等社交数据。
                _StatsLine(view: profileView),
              ],
            ),
          ),
          // 昵称旁已有「已认证」标签，通过后不再重复展示按钮；
          // 未通过时保留「去认证」入口（待审核/被驳回同样可进入查看状态）。
          if (!approved) ...[
            const SizedBox(width: 8),
            _AuthButton(onTap: onAuth),
          ],
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

/// 昵称下方的社交数据行：关注 / 粉丝 / 获赞。
///
/// 数据来自公开资料接口，加载中或失败时以「-」占位，避免数字跳变。
class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.view});

  final AsyncValue<UserProfileView> view;

  @override
  Widget build(BuildContext context) {
    final profile = view.valueOrNull;
    return Row(
      children: [
        _StatValue(label: '关注', value: profile?.followingCount),
        const SizedBox(width: 16),
        _StatValue(label: '粉丝', value: profile?.followerCount),
        const SizedBox(width: 16),
        _StatValue(label: '获赞', value: profile?.likeCount),
      ],
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value == null ? '-' : _compact(value!),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text1,
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text3)),
      ],
    );
  }

  /// 大数字压缩为「1.2万」，与列表页计数展示保持一致。
  static String _compact(int value) {
    if (value < 10000) return '$value';
    final wan = value / 10000;
    return '${wan.toStringAsFixed(wan >= 100 ? 0 : 1)}万';
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
                avatarUrl(avatar),
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

/// 「去认证」按钮：仅在实名未通过时展示（通过后由昵称旁的标签表达状态）。
class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryTint,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '去认证',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
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
class _QuickGrid extends StatefulWidget {
  const _QuickGrid({required this.ref, required this.user, required this.unread});

  final WidgetRef ref;
  final User user;
  final int unread;

  @override
  State<_QuickGrid> createState() => _QuickGridState();
}

class _QuickGridState extends State<_QuickGrid> {
  static const int _columns = 4;
  static const int _rows = 2;
  static const double _cellHeight = 84;
  static const int _perPage = _columns * _rows;

  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_QuickEntry> _entries() {
    final ref = widget.ref;
    final user = widget.user;
    return <_QuickEntry>[
      _QuickEntry(ref, Icons.star_outline, '收藏',
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.favorites)),
      _QuickEntry(ref, Icons.chat_bubble_outline, '消息',
          badge: widget.unread,
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.messages)),
      _QuickEntry(ref, Icons.forum_outlined, '会话',
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.chatSessionList)),
      _QuickEntry(ref, Icons.person_outline, '个人主页',
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.userProfileUrl(0))),
      if (user.authorCapability) ...[
        _QuickEntry(ref, Icons.auto_awesome, 'AI 创作',
            onTap: (ctx, ref) =>
                AuthGuard.pushProtected(ctx, ref, target: RoutePath.aiCenter)),
        _QuickEntry(ref, Icons.approval, '我的印章',
            onTap: (ctx, ref) =>
                AuthGuard.pushProtected(ctx, ref, target: RoutePath.mySeal)),
        _QuickEntry(ref, Icons.bar_chart, '创作者后台',
            onTap: (ctx, ref) =>
                AuthGuard.pushProtected(ctx, ref, target: RoutePath.creatorBackend)),
      ],
      if (user.isClient) ...[
        _QuickEntry(ref, Icons.fact_check_outlined, '我的选品'),
        _QuickEntry(ref, Icons.campaign_outlined, '需求发布'),
        _QuickEntry(ref, Icons.movie_outlined, '短剧管理'),
        _QuickEntry(ref, Icons.approval, '我的印章',
            onTap: (ctx, ref) =>
                AuthGuard.pushProtected(ctx, ref, target: RoutePath.mySeal)),
      ],
      _QuickEntry(ref, Icons.account_balance_wallet_outlined, '交易管理',
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.tradeManagement)),
      _QuickEntry(ref, Icons.card_giftcard, '福利',
          onTap: (ctx, ref) =>
              AuthGuard.pushProtected(ctx, ref, target: RoutePath.welfareCenter)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    // 每页 2 行 × 4 列；多余按钮进入后续页，横向滑动切换。
    final pages = <List<_QuickEntry>>[];
    for (var i = 0; i < entries.length; i += _perPage) {
      pages.add(entries.sublist(i, (i + _perPage).clamp(0, entries.length)));
    }
    if (pages.isEmpty) pages.add(const []);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / _columns;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _cellHeight * _rows,
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, pageIndex) {
                  return Wrap(
                    children: [
                      for (final entry in pages[pageIndex])
                        SizedBox(width: cellWidth, height: _cellHeight, child: entry),
                    ],
                  );
                },
              ),
            ),
            if (pages.length > 1) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.primary : AppColors.divider,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],
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
                  child: Text('书架暂无作品，去首页添加吧',
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

/// 竖版书封：优先展示真实封面图，缺失/加载失败时回退到 3:4 渐变底 + 书名
/// （对照原型 `.book .cv.g1/g2/g3` 的三套蓝色系书封）。
///
/// 修复：原实现固定渲染「渐变底 + 书名白字」，导致书架预览显示名字而非
/// 作品真实封面，与详情页/书城（WorkCover 封面图）不一致；现改为封面图优先。
class _ShelfBook extends StatelessWidget {
  const _ShelfBook({required this.work, required this.gradientIndex});

  final BookItem work;
  final int gradientIndex;

  // 对照原型 app.css `.book .cv.g1/g2/g3` 的三套蓝色系书封渐变（兜底用）。
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
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: AppColors.cardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: work.cover.isEmpty ? _fallback() : _coverImage(),
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

  /// 真实封面图：与详情页/书城同一份 cover 数据、同一套 [AppConfig.resolveAssetUrl] 归一，
  /// 撑满网格并裁切；加载失败回退到渐变书封。
  Widget _coverImage() => Image.network(
        AppConfig.resolveAssetUrl(work.cover),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _fallback(),
      );

  /// 封面缺失/加载失败时的兜底书封：蓝色渐变 + 左侧书脊线 + 书名白字。
  Widget _fallback() => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradients[gradientIndex % _gradients.length],
          ),
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
      );
}
