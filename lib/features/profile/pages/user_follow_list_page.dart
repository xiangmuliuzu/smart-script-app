import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/avatar_url.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/data/user_social_models.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 关注 / 粉丝列表（§1.7）。点击列表项进入对应用户的个人主页。
class UserFollowListPage extends ConsumerStatefulWidget {
  const UserFollowListPage({super.key, required this.userId, required this.showFollowing});

  final int userId;

  /// true=关注列表（我关注的人）；false=粉丝列表（关注我的人）。
  final bool showFollowing;

  @override
  ConsumerState<UserFollowListPage> createState() => _UserFollowListPageState();
}

class _UserFollowListPageState extends ConsumerState<UserFollowListPage> {
  /// 每行的关注态（本地覆盖，用于在列表内即时切换按钮文案）。
  final Map<int, bool> _overrides = {};
  final Set<int> _busy = {};

  Future<void> _toggle(UserSummary item) async {
    if (_busy.contains(item.userId)) return;
    final repo = ref.read(userSocialRepositoryProvider);
    final current = _overrides[item.userId] ?? item.isFollowing;
    setState(() => _busy.add(item.userId));
    try {
      final result = current ? await repo.unfollow(item.userId) : await repo.follow(item.userId);
      if (mounted) setState(() => _overrides[item.userId] = result.following);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy.remove(item.userId));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final async = widget.showFollowing
        ? ref.watch(userFollowingProvider(widget.userId))
        : ref.watch(userFollowersProvider(widget.userId));
    final myId = ref.watch(authControllerProvider).user?.userId ?? 0;

    return UserCenterScaffold(
      title: widget.showFollowing ? '关注' : '粉丝',
      actions: null,
      body: async.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(widget.showFollowing
              ? userFollowingProvider(widget.userId)
              : userFollowersProvider(widget.userId)),
        ),
        data: (list) => list.isEmpty
            ? EmptyView(message: widget.showFollowing ? '还没有关注任何人' : '还没有粉丝')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (context, index) {
                  final item = list[index];
                  final following = _overrides[item.userId] ?? item.isFollowing;
                  final isMe = item.userId == myId;
                  return _UserRow(
                    item: item,
                    following: following,
                    showButton: !isMe,
                    busy: _busy.contains(item.userId),
                    onTap: () => context.push(RoutePath.userProfileUrl(item.userId)),
                    onToggle: () => _toggle(item),
                  );
                },
              ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.item,
    required this.following,
    required this.showButton,
    required this.busy,
    required this.onTap,
    required this.onToggle,
  });

  final UserSummary item;
  final bool following;
  final bool showButton;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final nickname = item.nickname.isEmpty ? '未设置用户名称' : item.nickname;
    final url = avatarUrl(item.avatar);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipOval(
              child: Container(
                width: 44,
                height: 44,
                color: AppColors.primaryTint,
                child: url.isEmpty
                    ? Center(child: Text(nickname.substring(0, 1),
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)))
                    : Image.network(url, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person, color: AppColors.text3)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text1)),
                  const SizedBox(height: 2),
                  Text(
                    item.bio?.isNotEmpty == true ? item.bio! : '这个人很懒，什么都没写~',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            if (showButton)
              SizedBox(
                height: 30,
                child: following
                    ? OutlinedButton(
                        onPressed: busy ? null : onToggle,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.text2,
                          side: const BorderSide(color: AppColors.divider),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('已关注', style: TextStyle(fontSize: 12)),
                      )
                    : ElevatedButton(
                        onPressed: busy ? null : onToggle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: Size.zero,
                          elevation: 0,
                        ),
                        child: const Text('+ 关注', style: TextStyle(fontSize: 12)),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
