import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';

/// 工作台 Tab1：章节目录（写作范式，默认选中）。
///
/// 数据源为工作台详情的章节列表（随 A 套作品详情一次下发，含正文与 isFree/status）；
/// 点击章节进入全屏写作编辑器；可编辑状态下支持滑动删除（删除走 B 套章节接口）。
/// 章节行展示「试读」「已隐藏」徽标，便于作者核对免费试读与目录可见性。
class WorkChapterTab extends ConsumerWidget {
  const WorkChapterTab({
    super.key,
    required this.workId,
    required this.chapters,
    required this.editable,
  });

  final int workId;
  final List<AuthorChapterItem> chapters;

  /// 是否可编辑（草稿 / 待修改 / 已驳回）；审核中与已发布为只读。
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (chapters.isEmpty) {
      return Stack(
        children: [
          const EmptyView(
            message: '还没有章节，点击右下角开始写第一章',
            icon: Icons.edit_note_outlined,
          ),
          if (editable) _WriteButton(onTap: () => _openEditor(context, null)),
        ],
      );
    }
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: chapters.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 0.5, color: AppColors.divider),
          itemBuilder: (context, index) {
            final chapter = chapters[index];
            return _ChapterTile(
              chapter: chapter,
              editable: editable,
              onTap: () => _openEditor(context, chapter),
              onDelete: () => _confirmDelete(context, ref, chapter),
            );
          },
        ),
        if (editable) _WriteButton(onTap: () => _openEditor(context, null)),
      ],
    );
  }

  /// 打开全屏写作编辑器（新建 chapterId=0 / 编辑 chapterId 非 0）。
  void _openEditor(BuildContext context, AuthorChapterItem? chapter) {
    context.push(RoutePath.chapterWriteUrl(
      workId: workId,
      chapterId: chapter?.chapterId,
    ));
  }

  /// 滑动删除确认 → 调接口 → 刷新工作台。
  Future<bool> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AuthorChapterItem chapter,
  ) async {
    final title = chapter.chapterTitle.isEmpty
        ? '第 ${chapter.chapterNo} 章'
        : '《${chapter.chapterTitle}》';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除章节'),
        content: Text('确定删除 $title 吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await ref
          .read(authorWorkRepositoryProvider)
          .deleteChapter(chapter.chapterId);
      ref.invalidate(authorWorkDetailProvider(workId));
      return true;
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return false;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请稍后重试')),
        );
      }
      return false;
    }
  }
}

class _WriteButton extends StatelessWidget {
  const _WriteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: FloatingActionButton.extended(
        onPressed: onTap,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('写新章节', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

/// 章节行：滑动删除 + 点击进入编辑。
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.editable,
    required this.onTap,
    required this.onDelete,
  });

  final AuthorChapterItem chapter;
  final bool editable;
  final VoidCallback onTap;

  /// 返回 true=删除成功（Dismissible 会移除），false=取消或失败（回弹）。
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final title = chapter.chapterTitle.isEmpty
        ? '第 ${chapter.chapterNo} 章'
        : '第 ${chapter.chapterNo} 章 · ${chapter.chapterTitle}';
    return Dismissible(
      key: ValueKey(chapter.chapterId),
      direction: editable
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        color: AppColors.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: AppColors.card,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${chapter.wordCount} 字',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.text3),
                    ),
                  ],
                ),
              ),
              if (chapter.isFree)
                const _ChapterBadge(text: '试读', color: AppColors.primary),
              if (chapter.isFree && chapter.isHidden) const SizedBox(width: 6),
              if (chapter.isHidden)
                const _ChapterBadge(text: '已隐藏', color: AppColors.text3),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// 章节状态徽标（试读 / 已隐藏）。
class _ChapterBadge extends StatelessWidget {
  const _ChapterBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
