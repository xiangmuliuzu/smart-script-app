import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/common_views.dart';
import 'data/seal_models.dart';
import 'data/seal_providers.dart';

/// 我的印章页面（个人印章管理）。
///
/// 功能：
/// 1. 查看印章列表（通常只有 1 条记录）
/// 2. 上传印章图片（首次提交）
/// 3. 查看审核状态、驳回原因
/// 4. 重新提交（驳回后）
/// 5. 停用印章（审核通过后）
class MySealPage extends ConsumerWidget {
  const MySealPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sealsAsync = ref.watch(mySealsProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('我的印章'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePath.sealUpload),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('上传印章'),
      ),
      body: sealsAsync.when(
        loading: () => const LoadingView(),
        error: (error, stack) => ErrorView(
          message: '加载失败: $error',
          onRetry: () => ref.invalidate(mySealsProvider),
        ),
        data: (seals) {
          if (seals.isEmpty) {
            return _EmptyState(
              onUpload: () => context.push(RoutePath.sealUpload),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(mySealsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: seals.length,
              itemBuilder: (context, index) {
                final seal = seals[index];
                return _SealCard(
                  seal: seal,
                  onTap: () => context.push('${RoutePath.sealDetail}/${seal.sealId}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 空状态（无印章时显示）。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 80,
            color: AppColors.text3.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '您还没有上传印章',
            style: TextStyle(fontSize: 16, color: AppColors.text2),
          ),
          const SizedBox(height: 8),
          const Text(
            '上传印章后可用于版权认证',
            style: TextStyle(fontSize: 14, color: AppColors.text3),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onUpload,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.upload_file),
            label: const Text('立即上传'),
          ),
        ],
      ),
    );
  }
}

/// 印章卡片。
class _SealCard extends StatelessWidget {
  const _SealCard({
    required this.seal,
    required this.onTap,
  });

  final SealItem seal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      seal.sealName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusTag(seal.reviewStatus, seal.reviewStatusLabel),
                ],
              ),
              const SizedBox(height: 8),
              // 印章图片缩略图行
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      AppConfig.resolveAssetUrl(seal.sealImageUrl),
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        width: 50,
                        height: 50,
                        color: AppColors.fill,
                        child: const Icon(Icons.image_not_supported, color: AppColors.text3, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoItem(
                          Icons.verified,
                          '印章状态: ${seal.sealStatusLabel}',
                        ),
                        const SizedBox(height: 4),
                        if (seal.createTime != null)
                          _buildInfoItem(
                            Icons.access_time,
                            formatDate(seal.createTime),
                          ),
                        if (seal.reviewTime != null)
                          _buildInfoItem(
                            Icons.check_circle,
                            '审核时间: ${formatDate(seal.reviewTime)}',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              // 驳回原因
              if (seal.rejectReason != null && seal.rejectReason!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '驳回原因: ${seal.rejectReason}',
                          style: const TextStyle(fontSize: 13, color: AppColors.text2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTag(String status, String label) {
    Color bgColor;
    Color textColor;
    switch (status) {
      case 'pending':
        bgColor = AppColors.warning.withOpacity(0.1);
        textColor = AppColors.warning;
      case 'approved':
        bgColor = AppColors.success.withOpacity(0.1);
        textColor = AppColors.success;
      case 'rejected':
        bgColor = AppColors.danger.withOpacity(0.1);
        textColor = AppColors.danger;
      default:
        bgColor = AppColors.fill;
        textColor = AppColors.text2;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: textColor),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.text3),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.text2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String formatDate(String? dateTime) {
    if (dateTime == null) return '-';
    // 简单格式化：2024-01-01 10:00:00 -> 01-01 10:00
    if (dateTime.length >= 16) {
      return dateTime.substring(5, 16);
    }
    return dateTime;
  }
}
