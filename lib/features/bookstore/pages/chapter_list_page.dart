import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';

/// 作品章节目录（B 模块，接口 2.7.3 作品章节目录）。
///
/// 公开页，游客可读。可读性由服务端按作品试读配置判定（`readable`），
/// 客户端只做展示与跳转，不自行推算试读范围。
class ChapterListPage extends ConsumerWidget {
  const ChapterListPage({super.key, required this.workId, this.title});

  final int workId;

  /// 作品标题，仅用于页面标题展示。
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(chapterListProvider(workId));
    final appBarTitle = (title == null || title!.isEmpty) ? '章节目录' : title!;
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(appBarTitle)),
      body: listAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(chapterListProvider(workId)),
        ),
        data: (payload) {
          if (payload.chapters.isEmpty) {
            return const EmptyView(message: '暂无章节', icon: Icons.menu_book_outlined);
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(chapterListProvider(workId));
              await ref.read(chapterListProvider(workId).future);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _PreviewBanner(payload: payload),
                for (final chapter in payload.chapters)
                  _ChapterTile(
                    chapter: chapter,
                    onTap: () => _openChapter(context, chapter),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 可读章节跳阅读页；不可读章节只提示，不发起必然被拒的请求。
  void _openChapter(BuildContext context, ChapterSummary chapter) {
    if (!chapter.readable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该章节需合作或授权后查看')),
      );
      return;
    }
    context.push(RoutePath.chapterReadUrl(chapter.chapterId, title: chapter.chapterTitle));
  }
}

/// 试读状态提示条：明确告知可读范围，避免用户逐章试错。
class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.payload});

  final ChapterListPayload payload;

  @override
  Widget build(BuildContext context) {
    final bool opened = payload.previewEnabled && payload.previewEpisodes > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: opened ? AppColors.primaryTint : AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Row(
        children: [
          Icon(
            opened ? Icons.lock_open_outlined : Icons.lock_outline,
            size: 16,
            color: opened ? AppColors.primary : AppColors.text3,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              opened
                  ? '已开启试读：前 ${payload.previewEpisodes} 集可免费阅读'
                  : '本作品未开启试读，仅可查看章节目录',
              style: TextStyle(
                fontSize: 12,
                color: opened ? AppColors.primary : AppColors.text3,
              ),
            ),
          ),
          Text(
            '共 ${payload.total} 章',
            style: const TextStyle(fontSize: 12, color: AppColors.text3),
          ),
        ],
      ),
    );
  }
}

/// 目录行：可读章节带「试读」标记，未开读章节带锁。
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter, required this.onTap});

  final ChapterSummary chapter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name =
        chapter.chapterTitle.isEmpty ? '第 ${chapter.chapterNo} 章' : chapter.chapterTitle;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: chapter.readable ? AppColors.text1 : AppColors.text3,
                          ),
                        ),
                      ),
                      if (chapter.readable) ...[
                        const SizedBox(width: 8),
                        _Tag(text: chapter.isFree ? '免费' : '试读'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${chapter.wordCount} 字',
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            Icon(
              chapter.readable ? Icons.chevron_right : Icons.lock_outline,
              size: chapter.readable ? 20 : 16,
              color: AppColors.text3,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.primary)),
    );
  }
}