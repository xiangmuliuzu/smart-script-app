import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import 'data/seal_models.dart';
import 'data/seal_providers.dart';
import 'data/seal_repository.dart';
import 'material_preview_page.dart';

/// 印章详情页（查看印章详情、材料、审核状态、操作日志）。
///
/// 功能：
/// 1. 查看印章图片、材料 URL
/// 2. 查看审核状态、驳回原因
/// 3. 重新提交（驳回后）
/// 4. 停用印章（审核通过后）
/// 5. 查看操作日志
class SealDetailPage extends ConsumerWidget {
  const SealDetailPage({
    super.key,
    required this.sealId,
  });

  final int sealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(sealDetailProvider(sealId));

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('印章详情'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sealDetailProvider(sealId));
          await ref.read(sealDetailProvider(sealId).future);
        },
        child: detailAsync.when(
          data: (detail) {
            if (detail == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '印章不存在或无权限访问',
                      style: TextStyle(color: AppColors.text2),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(sealDetailProvider(sealId)),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            return _DetailContent(detail: detail);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('加载失败: $error', style: const TextStyle(color: AppColors.text3)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.invalidate(sealDetailProvider(sealId)),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 详情内容。
class _DetailContent extends ConsumerWidget {
  const _DetailContent({required this.detail});

  final SealDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SealInfoCard(detail: detail),
        const SizedBox(height: 12),
        _MaterialsCard(detail: detail),
        const SizedBox(height: 12),
        _StatusCard(detail: detail),
        const SizedBox(height: 12),
        _ManagementCard(detail: detail),
        if (detail.logs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _LogsCard(logs: detail.logs),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 印章信息卡片。
class _SealInfoCard extends StatelessWidget {
  const _SealInfoCard({required this.detail});

  final SealDetail detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('印章信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1)),
            const SizedBox(height: 12),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.rSmall),
                child: Image.network(
                  AppConfig.resolveAssetUrl(detail.sealImageUrl),
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    width: 200,
                    height: 200,
                    color: AppColors.fill,
                    child: const Icon(Icons.image_not_supported, size: 48, color: AppColors.text3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _InfoRow(label: '印章名称', value: detail.sealName),
            if (detail.createTime != null) _InfoRow(label: '提交时间', value: detail.createTime!),
            if (detail.reviewTime != null) _InfoRow(label: '审核时间', value: detail.reviewTime!),
          ],
        ),
      ),
    );
  }
}

/// 审核材料卡片。
class _MaterialsCard extends StatelessWidget {
  const _MaterialsCard({required this.detail});

  final SealDetail detail;

  @override
  Widget build(BuildContext context) {
    final materials = detail.materialUrlList;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('审核材料', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1)),
            const SizedBox(height: 12),
            if (materials.isEmpty)
              const Text('暂无审核材料', style: TextStyle(fontSize: 14, color: AppColors.text3))
            else
              ...materials.asMap().entries.map((entry) {
                final index = entry.key;
                final url = entry.value;
                final fullUrl = AppConfig.resolveAssetUrl(url);
                return Padding(
                  padding: EdgeInsets.only(bottom: index < materials.length - 1 ? 8 : 0),
                  child: Row(
                    children: [
                      const Icon(Icons.attachment, size: 16, color: AppColors.text3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '材料 ${index + 1}',
                          style: const TextStyle(fontSize: 14, color: AppColors.text2),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => MaterialPreviewPage(
                                materialUrl: fullUrl,
                                materialName: '材料 ${index + 1}',
                              ),
                            ),
                          );
                        },
                        child: const Text('查看'),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// 审核状态卡片。
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.detail});

  final SealDetail detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('审核状态', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1)),
            const SizedBox(height: 12),
            _InfoRow(label: '审核状态', value: detail.reviewStatusLabel),
            _InfoRow(label: '印章状态', value: detail.sealStatusLabel),
            if (detail.rejectReason != null && detail.rejectReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppRadius.rSmall),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                        SizedBox(width: 8),
                        Text('驳回原因', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.danger)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(detail.rejectReason!, style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 印章管理操作卡片。
class _ManagementCard extends ConsumerWidget {
  const _ManagementCard({required this.detail});

  final SealDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('印章管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1)),
            const SizedBox(height: 12),
            // 编辑按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  context.pushNamed(
                    RouteName.sealEdit,
                    pathParameters: {'sealId': '${detail.sealId}'},
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text('编辑印章'),
              ),
            ),
            const SizedBox(height: 8),
            // 删除按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete),
                label: const Text('删除印章'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              ),
            ),
            // 停用按钮（仅已审核通过且启用状态）
            if (detail.canDisable) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDisable(context, ref),
                  icon: const Icon(Icons.block),
                  label: const Text('停用印章'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后印章将无法恢复，是否确认删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      final repo = ref.read(sealRepositoryProvider);
      await repo.deleteSeal(detail.sealId);
      
      if (context.mounted) {
        showAppToast(context, '印章已删除');
        context.pop(); // 返回列表页
        ref.invalidate(mySealsProvider);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, '删除失败: $e');
      }
    }
  }

  Future<void> _confirmDisable(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认停用'),
        content: const Text('停用后印章将无法使用，是否确认停用？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.warning),
            child: const Text('确认停用'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      final repo = ref.read(sealRepositoryProvider);
      await repo.disableSeal(detail.sealId);
      
      if (context.mounted) {
        showAppToast(context, '印章已停用');
        ref.invalidate(sealDetailProvider(detail.sealId));
        ref.invalidate(mySealsProvider);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, '停用失败: $e');
      }
    }
  }
}

/// 操作日志卡片。
class _LogsCard extends StatelessWidget {
  const _LogsCard({required this.logs});

  final List<SealLog> logs;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('操作日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1)),
            const SizedBox(height: 12),
            ...logs.asMap().entries.map((entry) {
              final index = entry.key;
              final log = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: index < logs.length - 1 ? 12 : 0),
                child: _LogItem(log: log),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// 日志条目。
class _LogItem extends StatelessWidget {
  const _LogItem({required this.log});

  final SealLog log;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  log.operationTypeLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text1),
                ),
              ),
              if (log.createTime != null)
                Text(
                  log.createTime!,
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
            ],
          ),
          if (log.operatorName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '操作人: ${log.operatorName}',
              style: const TextStyle(fontSize: 13, color: AppColors.text2),
            ),
          ],
          if (log.reason != null && log.reason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '备注: ${log.reason}',
              style: const TextStyle(fontSize: 13, color: AppColors.text2),
            ),
          ],
        ],
      ),
    );
  }
}

/// 信息行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.text3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}
