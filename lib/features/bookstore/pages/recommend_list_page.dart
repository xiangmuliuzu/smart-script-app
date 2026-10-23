import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../data/content_providers.dart';
import '../widgets/bookstore_widgets.dart';

/// 热门精选推荐列表页（专属页面，最多显示 30 本）。
class RecommendListPage extends ConsumerWidget {
  const RecommendListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(hotWorksProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('热门精选推荐')),
      body: worksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加载失败: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(hotWorksProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (works) {
          if (works.isEmpty) {
            return const Center(child: Text('暂无推荐作品'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(hotWorksProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: works.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final work = works[index];
                return WorkListTile(
                  work: work,
                  onTap: () => context.push(RoutePath.workDetailUrl(work.workId)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
