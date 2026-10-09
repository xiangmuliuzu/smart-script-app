import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/create_models.dart';
import '../data/create_providers.dart';

/// 作品审核状态（APP 页面15，接口 2.9.6）。
///
/// status 为作品状态枚举，reviewResult 为最近一次审核结论，reviewComment 可为空。
class ReviewStatusPage extends ConsumerWidget {
  const ReviewStatusPage({super.key, required this.workId, this.title});

  final int workId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(reviewStatusProvider(workId));
    final name = title;
    return UserCenterScaffold(
      title: (name == null || name.isEmpty) ? '审核状态' : '审核状态 · $name',
      body: statusAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(reviewStatusProvider(workId)),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(ReviewStatus status) {
    final comment = status.reviewComment;
    final hasComment = comment != null && comment.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              _InfoRow(label: '作品状态', value: status.statusLabel),
              _InfoRow(label: '审核结论', value: status.reviewResultLabel),
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
              const Text('审核意见', style: TextStyle(color: AppColors.text2)),
              const SizedBox(height: 8),
              Text(
                hasComment ? comment : '暂无审核意见',
                style: TextStyle(
                  color: hasComment ? AppColors.text1 : AppColors.text3,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            '审核结论由平台审核人员给出；如需修改，请回到编辑页更新内容后重新提交。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(color: AppColors.text2)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '-' : value,
                style: const TextStyle(color: AppColors.text1)),
          ),
        ],
      ),
    );
  }
}