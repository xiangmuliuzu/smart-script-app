import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/auth_providers.dart';
import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/common_views.dart';
import 'data/content_providers.dart';
import 'data/content_repository.dart';

/// 书城（A6 示例业务主流程，B 模块）。
///
/// 公开列表：游客可读，不需要登录；「我的书架」是受保护入口，
/// 由 [AuthGuard.pushProtected] 统一拦截（未登录先登录，登录后回到书架）。
class BookstorePage extends ConsumerWidget {
  const BookstorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(worksProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('书城'),
        actions: [
          TextButton.icon(
            onPressed: () => AuthGuard.pushProtected(
              context,
              ref,
              target: RoutePath.bookshelf,
            ),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('我的书架'),
          ),
        ],
      ),
      body: worksAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(worksProvider),
        ),
        data: (payload) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(worksProvider),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              _IdentityBanner(
                guest: payload.identity.guest,
                nickname: auth.user?.nickname,
              ),
              const SizedBox(height: 12),
              Container(
                color: AppColors.card,
                child: Column(
                  children: [
                    for (final work in payload.works) _WorkCard(work: work),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 身份横幅：展示「游客可读 / 已登录个性化」这条跨模块身份能力的可见结果。
class _IdentityBanner extends StatelessWidget {
  const _IdentityBanner({required this.guest, required this.nickname});

  final bool guest;
  final String? nickname;

  @override
  Widget build(BuildContext context) {
    final name = nickname ?? '';
    final text = guest
        ? '游客浏览模式：登录后可同步书架与下载权限'
        : '已登录${name.isEmpty ? '' : '：$name'}，书架已同步';
    return Container(
      color: guest ? AppColors.primaryTint : AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(guest ? Icons.public : Icons.verified_user_outlined,
              size: 18, color: guest ? AppColors.primary : AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.text2)),
          ),
        ],
      ),
    );
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({required this.work});

  final WorkItem work;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.article_outlined, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  work.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text1),
                ),
                const SizedBox(height: 4),
                Text(
                  '${work.authorName} · ${work.category}',
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
                const SizedBox(height: 4),
                Text(
                  '${work.wordCount} 字 · ${work.freeToRead ? '免费阅读' : '需购买'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
