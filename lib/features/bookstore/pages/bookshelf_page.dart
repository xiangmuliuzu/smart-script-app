import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/real_name_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/content_providers.dart';
import '../data/content_repository.dart';

/// 我的书架（A6 示例受保护主流程，契约 A6-IDENTITY-CONTRACT-v1 §2.3）。
///
/// 演示要点：
///   - 进入前由 [AuthGuard.requireLogin] 拦截；未登录会先登录再回到本页；
///   - 下载能力由实名状态决定（业务准入），与角色授权无关；
///   - 页面不自行拼装身份，身份摘要由后端统一下发。
class BookshelfPage extends ConsumerWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelfAsync = ref.watch(shelfProvider);

    return UserCenterScaffold(
      title: '我的书架',
      body: shelfAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(shelfProvider),
        ),
        data: (payload) => _buildBody(context, ref, payload),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ShelfPayload payload) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(shelfProvider),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _IdentityCard(payload: payload),
          const SizedBox(height: 12),
          if (payload.works.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: EmptyView(message: '书架暂无作品', icon: Icons.menu_book_outlined),
            )
          else
            Container(
              color: AppColors.card,
              child: Column(
                children: [
                  for (final work in payload.works)
                    _WorkRow(
                      work: work,
                      downloadable: payload.downloadable,
                      onDownload: () => _download(context, ref, payload, work),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 身份摘要卡片：直接展示后端下发的身份字段，用于验证跨模块身份联通。
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.payload});

  final ShelfPayload payload;

  @override
  Widget build(BuildContext context) {
    final identity = payload.identity;
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                '身份摘要（由服务端下发）',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _line('登录状态', identity.authenticated ? '已登录' : '游客'),
          _line('用户 ID', identity.userId?.toString() ?? '（无，游客不伪造 ID）'),
          _line('账号类型', identity.accountType ?? '-'),
          _line('实名状态', identity.realNameStatus),
          _line('作者能力', identity.authorCapability ? '已开通' : '未开通'),
          _line('角色', identity.roleCodes.isEmpty ? '无' : identity.roleCodes.join('、')),
          _line('权限数', '${identity.permissionCodes.length}'),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13, color: AppColors.text1)),
            ),
          ],
        ),
      );
}

/// 下载素材：演示「实名准入」守卫与「角色授权」分开判断。
///
/// 该动作与角色无关，只由实名状态决定准入；未通过时 [RealNameGuard] 会引导去认证。
Future<void> _download(
  BuildContext context,
  WidgetRef ref,
  ShelfPayload payload,
  WorkItem work,
) async {
  final allowed = await RealNameGuard.requireApproved(
    context,
    ref,
    reason: '下载《${work.title}》素材需要先完成实名认证。',
    target: RoutePath.bookshelf,
  );
  if (!allowed || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已开始下载《${work.title}》（示例动作，未接入真实下载）')),
  );
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({
    required this.work,
    required this.downloadable,
    required this.onDownload,
  });

  final WorkItem work;
  final bool downloadable;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(work.title,
                    style: const TextStyle(fontSize: 15, color: AppColors.text1)),
                const SizedBox(height: 4),
                Text(
                  '${work.authorName} · ${work.category} · ${work.wordCount} 字',
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
          // 下载入口的可用性由实名准入决定（与角色授权分开判断）；
          // 未通过时点击会由 RealNameGuard 引导去实名认证。
          IconButton(
            onPressed: onDownload,
            icon: Icon(
              downloadable ? Icons.download_outlined : Icons.lock_outline,
              size: 20,
              color: downloadable ? AppColors.primary : AppColors.text3,
            ),
            tooltip: downloadable ? '下载素材' : '需实名认证',
          ),
        ],
      ),
    );
  }
}
