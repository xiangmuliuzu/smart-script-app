import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';

/// 「开始创作」方式选择底部弹层（作品列表「新建」与底部导航「创作」共用）。
///
/// 返回 `'ai'`（AI 创作）/ `'storyboard'`（基于已有作品的 AI 分镜）/
/// `'editor'`（自己编辑）；关闭弹层返回 null。
Future<String?> showCreateChoice(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('开始创作',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
            title: const Text('AI 创作'),
            subtitle: const Text('描述灵感，先生成作品资料；确认后逐章成文。'),
            onTap: () => Navigator.of(sheetContext).pop('ai'),
          ),
          ListTile(
            leading: const Icon(Icons.movie_creation_outlined,
                color: AppColors.primary),
            title: const Text('创作分镜'),
            subtitle: const Text('选一部已有作品，把某一集转成分镜。'),
            onTap: () => Navigator.of(sheetContext).pop('storyboard'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: AppColors.text2),
            title: const Text('自己编辑'),
            subtitle: const Text('新建空白作品，或导入已写好的剧本。'),
            onTap: () => Navigator.of(sheetContext).pop('editor'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// 「创作分镜」：选择本人一部作品后打开 AI 分镜页。
///
/// 分镜必须挂到已有作品的一个章节上（后端分镜目录按作品 + 章节存储），
/// 因此底部导航「创作」与「我的作品」新建入口共用这一套「先选作品」流程。
Future<void> pickWorkForStoryboard(BuildContext context, WidgetRef ref) async {
  List<AuthorWorkItem> works;
  try {
    works = await ref.read(myWorksProvider('all').future);
  } catch (_) {
    if (context.mounted) showAppToast(context, '作品列表加载失败，请稍后重试');
    return;
  }
  if (!context.mounted) return;
  if (works.isEmpty) {
    showAppToast(context, '还没有作品，先创建一部作品再为它创作分镜');
    return;
  }
  final picked = await showModalBottomSheet<AuthorWorkItem>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Text('选择作品',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final work in works)
            ListTile(
              title: Text(work.title.isEmpty ? '未命名作品' : work.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${work.statusLabel} · ${work.wordCount} 字'),
              onTap: () => Navigator.of(sheetContext).pop(work),
            ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  context.push(RoutePath.aiStoryboardUrl(workId: picked.workId));
}
