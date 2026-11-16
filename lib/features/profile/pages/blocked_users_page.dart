import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/avatar_url.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/data/user_social_models.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 黑名单列表：展示当前用户拉黑的用户，可进入对方主页或直接解除拉黑。
class BlockedUsersPage extends ConsumerStatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  ConsumerState<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends ConsumerState<BlockedUsersPage> {
  final Set<int> _busy = {};

  Future<void> _unblock(UserSummary item) async {
    if (_busy.contains(item.userId)) return;
    setState(() => _busy.add(item.userId));
    try {
      await ref.read(userSocialRepositoryProvider).unblock(item.userId);
      ref.invalidate(blockedUsersProvider);
      // 对方主页若已缓存「已拉黑」态，一并失效，回到主页时按钮恢复「关注」。
      ref.invalidate(userProfileViewProvider(item.userId));
      if (mounted) _toast('已解除黑名单');
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
    final async = ref.watch(blockedUsersProvider);
    return UserCenterScaffold(
      title: '黑名单',
      actions: null,
      body: async.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(blockedUsersProvider),
        ),
        data: (list) => list.isEmpty
            ? const EmptyView(message: '黑名单中还没有用户')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (context, index) {
                  final item = list[index];
                  return _BlockedUserRow(
                    item: item,
                    busy: _busy.contains(item.userId),
                    onTap: item.userId > 0
                        ? () => context.push(RoutePath.userProfileUrl(item.userId))
                        : null,
                    onUnblock: () => _unblock(item),
                  );
                },
              ),
      ),
    );
  }
}

class _BlockedUserRow extends StatelessWidget {
  const _BlockedUserRow({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onUnblock,
  });

  final UserSummary item;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback onUnblock;

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
                    ? Center(
                        child: Text(
                          nickname.substring(0, 1),
                          style: const TextStyle(
                            color: AppColors.text1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person, color: AppColors.text3),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text1,
                    ),
                  ),
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
            SizedBox(
              height: 30,
              child: OutlinedButton(
                onPressed: busy ? null : onUnblock,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text2,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: Size.zero,
                ),
                child: const Text('解除', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
