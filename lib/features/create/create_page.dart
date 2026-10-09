import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';

/// 创作入口（底部导航「创作」tab，接口文档 2.9）。
///
/// 提供上传新作品、草稿箱入口；AI 写作 / AI 润色属于 E 模块（2.9.10~2.9.13），
/// 本批未接入，点击仅提示，不调用任何接口。
class CreatePage extends StatelessWidget {
  const CreatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('创作')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '发布你的剧本作品',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '剧本上传 / AI 写作 / AI 润色 / 草稿箱',
            style: TextStyle(color: AppColors.text3, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _EntryCard(
            icon: Icons.cloud_upload_outlined,
            title: '上传新作品',
            subtitle: '填写标题、分类与简介，上传封面与剧本文件',
            onTap: () => context.push(RoutePath.workUpload),
          ),
          const SizedBox(height: 12),
          _EntryCard(
            icon: Icons.edit_note_outlined,
            title: '草稿箱',
            subtitle: '查看未发布的草稿，可继续编辑或删除',
            onTap: () => context.push(RoutePath.draftList),
          ),
          const SizedBox(height: 12),
          _EntryCard(
            icon: Icons.auto_awesome_outlined,
            title: 'AI 写作 / AI 润色',
            subtitle: '智能生成与润色剧本内容',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('AI 创作能力属于 E 模块，暂未接入')),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.rSmall),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: AppColors.text3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}