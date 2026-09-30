import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';

/// 章节正文（B 模块，接口 2.7.4 章节正文）。
///
/// 公开页，游客可试读。超出试读范围时后端返回 code=403 且 data 不含正文，
/// 由 [ApiClient] 抛 [ApiException]，本页落到「试读结束」提示而非通用错误态。
class ChapterReadPage extends ConsumerWidget {
  const ChapterReadPage({super.key, required this.chapterId, this.title});

  final int chapterId;

  /// 章节标题，仅用于加载期间的页面标题展示。
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(chapterDetailProvider(chapterId));
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(
        title: Text((title == null || title!.isEmpty) ? '正文' : title!),
      ),
      body: detailAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) {
          // 403 = 试读结束：属于正常业务边界，不作为错误展示。
          if (error is ApiException && error.code == 403) {
            return _LockedView(message: error.message);
          }
          return ErrorView(
            message: error is ApiException ? error.message : '加载失败，请稍后重试',
            onRetry: () => ref.invalidate(chapterDetailProvider(chapterId)),
          );
        },
        data: (detail) {
          final content = detail.content;
          if (!detail.readable || content == null || content.isEmpty) {
            return const _LockedView(message: '试读结束，请合作或授权后查看完整剧本');
          }
          return _Reader(detail: detail, content: content);
        },
      ),
    );
  }
}

/// 正文排版：按换行切段，段间留白，长文行高放宽便于阅读。
class _Reader extends StatelessWidget {
  const _Reader({required this.detail, required this.content});

  final ChapterDetail detail;
  final String content;

  @override
  Widget build(BuildContext context) {
    final paragraphs = content.split('\n');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Text(
          detail.chapterTitle.isEmpty ? '第 ${detail.chapterNo} 章' : detail.chapterTitle,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.text1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '共 ${detail.wordCount} 字',
          style: const TextStyle(fontSize: 12, color: AppColors.text3),
        ),
        const SizedBox(height: 20),
        for (final line in paragraphs)
          if (line.trim().isEmpty)
            const SizedBox(height: 10)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                line,
                style: const TextStyle(fontSize: 16, height: 1.9, color: AppColors.text2),
              ),
            ),
        const SizedBox(height: 16),
        const Text(
          '— 本章结束 —',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.text3),
        ),
      ],
    );
  }
}

/// 试读结束提示：说明边界并提供返回入口。
class _LockedView extends StatelessWidget {
  const _LockedView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: AppColors.text3),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.text2, height: 1.6),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                }
              },
              child: const Text('返回目录'),
            ),
          ],
        ),
      ),
    );
  }
}