import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/data/content_providers.dart';
import '../../bookstore/pages/work_storyboard_page.dart';

String authorStoryboardStatus(Object? status) => switch (status) {
      'approved' => '审核通过',
      'rejected' => '未通过审核',
      'ai_reviewing' => 'AI 审核中',
      'pending' => '待人工审核',
      _ => '待审核',
    };

Map<String, dynamic>? storyboardForChapter(
    List<Map<String, dynamic>>? items, int chapterId) {
  if (chapterId <= 0 || items == null) return null;
  for (final item in items) {
    if (item['chapterId'].toString() == chapterId.toString()) return item;
  }
  return null;
}

void openAuthorStoryboard(
    BuildContext context, int workId, Map<String, dynamic> item) {
  final id = int.tryParse(item['storyboardId'].toString());
  if (id == null) return;
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => StoryboardReadPage(
      workId: workId,
      storyboardId: id,
      title: (item['chapterTitle'] ?? '分镜').toString(),
    ),
  ));
}

/// 本人作品的分镜目录。读取后端作者视图，包含审核中和未通过的记录。
class WorkStoryboardTab extends ConsumerWidget {
  const WorkStoryboardTab({
    super.key,
    required this.workId,
    required this.editable,
    required this.hasChapters,
  });

  final int workId;
  final bool editable;
  final bool hasChapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = workStoryboardsProvider(workId);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  !hasChapters ? '先保存一章剧本，即可开始分镜。' : '每条分镜关联一个已有章节。',
                  style: const TextStyle(color: AppColors.text2),
                ),
              ),
              if (editable && hasChapters)
                TextButton.icon(
                  onPressed: () =>
                      context.push(RoutePath.aiStoryboardUrl(workId: workId)),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('创作分镜'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ref.watch(provider).when(
                loading: () => const LoadingView(message: '正在加载分镜'),
                error: (error, _) => ErrorView(
                  message: error is ApiException ? error.message : '分镜加载失败，请重试',
                  onRetry: () => ref.invalidate(provider),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyView(
                        message: '还没有分镜',
                        icon: Icons.movie_filter_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(provider);
                          try {
                            await ref.read(provider.future);
                          } on Object {/* 错误由上方 ErrorView 展示。 */}
                        },
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final status =
                                authorStoryboardStatus(item['status']);
                            final reason = item['rejectReason'];
                            return ListTile(
                              leading: const Icon(Icons.movie_filter_outlined),
                              title: Text(
                                  (item['chapterTitle'] ?? '未命名分镜').toString()),
                              subtitle: Text([
                                status,
                                if (item['status'] == 'approved')
                                  item['trialEnabled'] == true
                                      ? '已开启试读'
                                      : '未开启试读',
                                if (reason is String &&
                                    reason.trim().isNotEmpty)
                                  reason,
                              ].join(' · ')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  openAuthorStoryboard(context, workId, item),
                            );
                          },
                        ),
                      ),
              ),
        ),
      ],
    );
  }
}
