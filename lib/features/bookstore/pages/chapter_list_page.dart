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
      backgroundColor: Colors.transparent,
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
                    unlocked: payload.unlocked,
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

/// 可读范围提示条：优先展示「已授权」，否则展示试读范围，避免用户逐章试错。
class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.payload});

  final ChapterListPayload payload;

  @override
  Widget build(BuildContext context) {
    // 已获授权时全文可读，试读范围不再是限制条件，故优先展示授权态
    final bool unlocked = payload.unlocked;
    final bool opened = payload.previewEnabled && payload.previewEpisodes > 0;
    final bool highlighted = unlocked || opened;
    final IconData icon = unlocked
        ? Icons.verified_outlined
        : (opened ? Icons.lock_open_outlined : Icons.lock_outline);
    final String message = unlocked
        ? '已获授权：可阅读全部章节'
        : (opened
            ? '已开启试读：前 ${payload.previewEpisodes} 集可免费阅读'
            : '本作品未开启试读，仅可查看章节目录');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.primaryTint : AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: highlighted ? AppColors.primary : AppColors.text3,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: highlighted ? AppColors.primary : AppColors.text3,
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

/// 目录行：可读章节带「免费 / 试读 / 已授权」标记，不可读章节带锁。
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter, required this.unlocked, required this.onTap});

  final ChapterSummary chapter;

  /// 作品是否已授权全文：为 true 时非免费章节的可读原因记为「已授权」。
  final bool unlocked;
  final VoidCallback onTap;

  /// 可读原因标记；不可读返回 null。
  String? get _readableTag {
    if (!chapter.readable) return null;
    if (chapter.isFree) return '免费';
    return unlocked ? '已授权' : '试读';
  }

  @override
  Widget build(BuildContext context) {
    final String name =
        chapter.chapterTitle.isEmpty ? '第 ${chapter.chapterNo} 章' : chapter.chapterTitle;
    final String? tag = _readableTag;
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
                      if (tag != null) ...[
                        const SizedBox(width: 8),
                        _Tag(text: tag),
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