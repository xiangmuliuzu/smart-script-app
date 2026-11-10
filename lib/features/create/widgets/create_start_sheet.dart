import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 「新建作品」方式选择底部弹层（作品列表「新建」与底部导航「创作」共用）。
///
/// 返回 `'ai'`（AI 创作）/ `'editor'`（自己编辑）；关闭弹层返回 null。
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
              child: Text('开始创作', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
            title: const Text('AI 创作'),
            subtitle: const Text('描述灵感，先生成大纲；确认后逐章成文，插入作品继续改。'),
            onTap: () => Navigator.of(sheetContext).pop('ai'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: AppColors.text2),
            title: const Text('自己编辑'),
            subtitle: const Text('直接新建作品，自己写或导入已完成的剧本文件。'),
            onTap: () => Navigator.of(sheetContext).pop('editor'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
