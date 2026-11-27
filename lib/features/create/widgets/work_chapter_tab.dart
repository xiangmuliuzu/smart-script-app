import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';
import '../data/chapter_meta_models.dart';

/// 工作台 Tab1：章节目录（写作范式，默认选中）。
///
/// 数据源为工作台详情的章节列表（随 A 套作品详情一次下发，含正文与 isFree/status）；
/// 点击章节进入全屏写作编辑器；可编辑状态下支持滑动删除（删除走 B 套章节接口）。
/// 章节行展示中文审核状态和试读标记，便于作者核对章节审核结果。
///
/// 新建章节入口由工作台底部按钮统一提供（本组件不再挂 FAB，避免重复入口）。
class WorkChapterTab extends ConsumerWidget {
  const WorkChapterTab({
    super.key,
    required this.workId,
    required this.chapters,
    required this.editable,
    this.metas = ChapterMetaTable.empty,
  });

  final int workId;
  final List<AuthorChapterItem> chapters;

  /// 是否可编辑（草稿 / 待修改 / 已驳回）；审核中为只读。
  final bool editable;

  /// 作品全部章节资料（本章概要与关系由它派生，列表只读展示状态）。
  final ChapterMetaTable metas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (chapters.isEmpty) {
      return const EmptyView(
        message: '还没有章节，点底部「新建章节」开始写第一章',
        icon: Icons.edit_note_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: chapters.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 0.5, color: AppColors.divider),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        return _ChapterTile(
          chapter: chapter,
          meta: metas.of(chapter.chapterNo),
          editable: editable,
          onTap: () => _openEditor(context, chapter),
          onDelete: () => _confirmDelete(context, ref, chapter),
        );
      },
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

/// 章节行：滑动删除 + 点击进入编辑。
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.meta,
    required this.editable,
    required this.onTap,
    required this.onDelete,
  });

  final AuthorChapterItem chapter;
  final ChapterMeta meta;
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
      direction: editable ? DismissDirection.endToStart : DismissDirection.none,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      _statusLine(chapter, meta),
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.text3),
                    ),
                  ],
                ),
              ),
              _ChapterBadge(
                text: chapter.statusLabel,
                color: chapter.isApproved
                    ? AppColors.success
                    : chapter.status == '2'
                        ? AppColors.danger
                        : AppColors.text3,
              ),
              if (chapter.isFree && chapter.isApproved)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: _ChapterBadge(
                    text: '试读',
                    color: AppColors.primary,
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// 章节进度一句话：已写正文 / 概要已定待写正文 / 待定概要。
String _statusLine(AuthorChapterItem chapter, ChapterMeta meta) {
  final words = chapter.wordCount > 0
      ? chapter.wordCount
      : chapter.content.replaceAll(RegExp(r'\s'), '').length;
  if (words > 0) {
    final hasSummary = chapter.summary.trim().isNotEmpty || meta.isAiDrafted;
    return hasSummary ? '已写 $words 字 · 概要已定' : '已写 $words 字';
  }
  if (chapter.summary.trim().isNotEmpty) return '概要已定 · 待写正文';
  if (meta.isAiDrafted) return 'AI 已起草概要 · 待写正文';
  return '待定概要';
}

/// 章节状态徽标。
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
