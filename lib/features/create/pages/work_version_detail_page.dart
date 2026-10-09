import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/create_models.dart';
import '../data/create_providers.dart';

/// 版本详情（接口 2.9.9，含 content 全文；非本人/不存在时后端按 404 拒绝）。
class WorkVersionDetailPage extends ConsumerWidget {
  const WorkVersionDetailPage({super.key, required this.versionId, this.title});

  final int versionId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(workVersionDetailProvider(versionId));
    final name = title;
    return UserCenterScaffold(
      title: (name == null || name.isEmpty) ? '版本详情' : '版本详情 · $name',
      body: detailAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(workVersionDetailProvider(versionId)),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(WorkVersionDetail detail) {
    final content = detail.content;
    final hasContent = content != null && content.isNotEmpty;
    final changeLog = detail.changeLog;
    final hasChangeLog = changeLog != null && changeLog.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'V${detail.versionNo}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail.createTime ?? '时间未知',
                style: const TextStyle(fontSize: 12, color: AppColors.text3),
              ),
              const SizedBox(height: 10),
              Text(
                hasChangeLog ? changeLog : '无变更说明',
                style: TextStyle(
                  fontSize: 13,
                  color: hasChangeLog ? AppColors.text2 : AppColors.text3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('版本内容', style: TextStyle(color: AppColors.text2)),
              const SizedBox(height: 8),
              if (hasContent)
                SelectableText(
                  content,
                  style: const TextStyle(
                    color: AppColors.text1,
                    fontSize: 14,
                    height: 1.6,
                  ),
                )
              else
                const Text('该版本无正文内容', style: TextStyle(color: AppColors.text3)),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}