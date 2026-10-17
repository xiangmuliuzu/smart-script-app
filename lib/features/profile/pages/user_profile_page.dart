import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/avatar_url.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/data/bookstore_models.dart';
import '../../bookstore/data/content_providers.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/data/user_social_models.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 个人主页（§1.7）。
///
/// 统一入口：查看自己或他人的公开主页。userId 为 0 时按「自己」处理。
/// 展示：头像/昵称/简介/注册时间 + 关注/粉丝/获赞（真实计数）+ 上架作品。
/// 他人主页显示「关注/已关注」按钮；自己的主页不显示关注按钮，右上角「···」进编辑资料。
class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.userId});

  final int userId;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  bool _busy = false;

  /// 乐观关注态：操作前用本地值渲染，服务端确认后以返回值覆盖。
  bool? _following;
  int? _followerCount;

  int get _targetUserId {
    if (widget.userId > 0) return widget.userId;
    return ref.read(authControllerProvider).user?.userId ?? 0;
  }

  Future<void> _toggleFollow(UserProfileView profile) async {
    if (_busy || profile.isSelf) return;
    final repo = ref.read(userSocialRepositoryProvider);
    final next = !(_following ?? profile.isFollowing);
    setState(() => _busy = true);
    try {
      final result = next ? await repo.follow(profile.userId) : await repo.unfollow(profile.userId);
      if (!mounted) return;
      setState(() {
        _following = result.following;
        _followerCount = result.followerCount;
      });
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openEdit() {
    AuthGuard.pushProtected(context, ref, target: RoutePath.profileEdit);
  }

  @override
  Widget build(BuildContext context) {
    final targetId = _targetUserId;
    final profileAsync = ref.watch(userProfileViewProvider(targetId));
    final isSelf = targetId == 0 || profileAsync.valueOrNull?.isSelf == true;

    return UserCenterScaffold(
      title: '个人主页',
      actions: [
        if (isSelf)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (value == 'edit') _openEdit();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑个人资料')),
            ],
          ),
      ],
      body: profileAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(userProfileViewProvider(targetId)),
        ),
        data: (profile) => _buildBody(profile),
      ),
    );
  }

  Widget _buildBody(UserProfileView profile) {
    final following = _following ?? profile.isFollowing;
    final followerCount = _followerCount ?? profile.followerCount;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Header(
          profile: profile,
          followerCount: followerCount,
          onFollow: () => _toggleFollow(profile),
          following: following,
          busy: _busy,
          onTapFollowing: () => _openFollowList(profile.userId, following: true),
          onTapFollowers: () => _openFollowList(profile.userId, following: false),
        ),
        // 作品区与全 App 一致：圆角白卡片浮在页面渐变背景上（不再用通栏白底）。
        AppCard(
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _WorksSection(authorId: profile.userId),
          ),
        ),
      ],
    );
  }

  void _openFollowList(int userId, {required bool following}) {
    context.push(RoutePath.userFollowListUrl(userId, following: following));
  }
}

/// 头部：头像/昵称/简介/注册时间 + 统计 + 关注按钮。
class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.followerCount,
    required this.following,
    required this.busy,
    required this.onFollow,
    required this.onTapFollowing,
    required this.onTapFollowers,
  });

  final UserProfileView profile;
  final int followerCount;
  final bool following;
  final bool busy;
  final VoidCallback onFollow;
  final VoidCallback onTapFollowing;
  final VoidCallback onTapFollowers;

  @override
  Widget build(BuildContext context) {
    final nickname = profile.nickname.isEmpty ? '未设置用户名称' : profile.nickname;
    return Container(
      // 不再自带渐变：顶部直接透出 AppPageBackground 的冰蓝渐变，与首页保持同一背景。
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(nickname: nickname, avatar: profile.avatar),
              const SizedBox(width: 14),
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
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text1,
                            ),
                          ),
                        ),
                        if (profile.isCreator) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.edit_note, size: 16, color: AppColors.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile.bio?.isNotEmpty == true ? profile.bio! : '这个人很懒，什么都没写~',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.text2),
                    ),
                    if (profile.registeredAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '加入时间 ${_formatDate(profile.registeredAt!)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.text3),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 自己的主页不显示任何按钮：编辑资料在右上角「···」菜单里。
              if (!profile.isSelf)
                _FollowButton(following: following, busy: busy, onTap: onFollow),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatItem(label: '关注', value: profile.followingCount, onTap: onTapFollowing),
              _StatItem(label: '粉丝', value: followerCount, onTap: onTapFollowers),
              _StatItem(label: '获赞', value: profile.likeCount, onTap: null),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.following, required this.busy, required this.onTap});

  final bool following;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: following
          ? OutlinedButton(
              onPressed: busy ? null : onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text2,
                side: const BorderSide(color: AppColors.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('已关注'),
            )
          : ElevatedButton(
              onPressed: busy ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                elevation: 0,
              ),
              child: const Text('+ 关注'),
            ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value, this.onTap});

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text1),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text3)),
          ],
        ),
      ),
    );
  }
}

/// 作品区域：上架作品封面网格；空/错误有对应状态。
class _WorksSection extends ConsumerWidget {
  const _WorksSection({required this.authorId});

  final int authorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(authorWorksProvider(authorId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text('作品',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text1)),
              const SizedBox(width: 6),
              Text(
                '${worksAsync.valueOrNull?.total ?? 0}',
                style: const TextStyle(fontSize: 14, color: AppColors.text3),
              ),
            ],
          ),
        ),
        worksAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: LoadingView(),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorView(
              message: error is ApiException ? error.message : '作品加载失败',
              onRetry: () => ref.invalidate(authorWorksProvider(authorId)),
            ),
          ),
          data: (page) => page.list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: EmptyView(message: '还没有发布作品'),
                )
              : _WorksGrid(works: page.list),
        ),
      ],
    );
  }
}

class _WorksGrid extends StatelessWidget {
  const _WorksGrid({required this.works});

  final List<BookItem> works;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        // 封面按 3:4 完整竖版展示，下方留出两行标题的高度。
        childAspectRatio: 0.56,
      ),
      itemCount: works.length,
      itemBuilder: (context, index) {
        final work = works[index];
        return GestureDetector(
          onTap: () => context.push(RoutePath.workDetailUrl(work.workId)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面按列宽等比撑满：3:4 的竖版封面完整显示，不再被固定高度裁切。
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.topCenter,
                    child: WorkCover(
                      url: work.cover,
                      width: constraints.maxWidth,
                      height: constraints.maxWidth * 4 / 3,
                      radius: AppRadius.rSmall,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                work.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.text1, height: 1.3),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nickname, this.avatar});

  final String nickname;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl(avatar);
    return ClipOval(
      child: Container(
        width: 64,
        height: 64,
        color: AppColors.primaryTint,
        child: url.isEmpty
            ? _fallback
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback),
      ),
    );
  }

  Widget get _fallback => Center(
        child: Text(
          nickname.isNotEmpty ? nickname.substring(0, 1) : '?',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.primary),
        ),
      );
}
