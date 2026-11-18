import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';

/// 作品分镜目录。
///
/// 入口位置：作品详情页「章节目录」下方，与章节目录同级，始终展示。
/// 数据范围：已上架作品中的审核通过分镜；正文是否可读由服务端按关联章节的
/// 试读设置和当前授权状态计算，客户端不自行放开内容。
class WorkStoryboardPage extends ConsumerWidget {
  const WorkStoryboardPage({super.key, required this.workId, this.title});

  final int workId;

  /// 作品标题，仅用于页面标题展示。
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storyboards = ref.watch(workStoryboardsProvider(workId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text((title == null || title!.isEmpty) ? '分镜目录' : '${title!} · 分镜目录'),
      ),
      body: storyboards.when(
        loading: () => const LoadingView(message: '正在加载分镜目录'),
        error: (_, __) => const EmptyView(
          message: '暂无分镜内容\n分镜生成或交付后，会按场次和镜号显示在这里。',
          icon: Icons.movie_filter_outlined,
        ),
        data: (items) => items.isEmpty
            ? const EmptyView(
                message: '暂无分镜内容\n分镜生成或交付后，会按场次和镜号显示在这里。',
                icon: Icons.movie_filter_outlined,
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _StoryboardCard(item: items[index], index: index),
              ),
      ),
    );
  }
}

class _StoryboardCard extends StatelessWidget {
  const _StoryboardCard({required this.item, required this.index});

  final Map<String, dynamic> item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final title = (item['chapterTitle'] ?? item['title'] ?? item['name'] ?? '未命名分镜').toString();
    final chapter = (item['chapterTitle'] ?? (item['chapterNo'] == null ? '作品级分镜' : '第 ${item['chapterNo']} 章')).toString();
    final shots = item['shotCount'] ?? item['totalShots'] ?? '—';
    final status = _statusLabel((item['status'] ?? '').toString());
    final readable = item['readable'] != false;
    final content = (item['content'] ?? item['description'] ?? '').toString().trim();
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryTint,
          child: Text('${index + 1}', style: const TextStyle(color: AppColors.primary)),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: readable
            ? const Icon(Icons.expand_more)
            : const Icon(Icons.lock_outline, size: 19, color: AppColors.text3),
        subtitle: Text('$chapter  ·  $shots 镜头  ·  $status${readable ? ' · 可试读' : ' · 暂未开放'}'),
        children: [
          if (!readable)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('该分镜暂未开放试读，请先完成授权或购买。', style: TextStyle(color: AppColors.text3)),
              ),
            )
          else if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectableText(content, style: const TextStyle(height: 1.6, color: AppColors.text2)),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(alignment: Alignment.centerLeft, child: Text('暂无分镜说明', style: TextStyle(color: AppColors.text3))),
            ),
        ],
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return '待人工审核';
      case 'ai_reviewing':
        return 'AI审核中';
      case 'approved':
        return '审核通过';
      case 'rejected':
        return '审核驳回';
      default:
        return '待审核';
    }
  }
}
