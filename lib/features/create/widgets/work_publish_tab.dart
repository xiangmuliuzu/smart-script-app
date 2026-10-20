import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';

/// 工作台 Tab3：发布与审核。
///
/// 展示作品状态/章节数/总字数 + 提交审核按钮 + 审核历史列表 + 版本管理入口。
/// 提交审核调 A 套 POST /users/me/works/{workId}/submit；
/// 审核记录调 A 套 GET /users/me/works/{workId}/review-records。
/// 已发布作品改动后可再次提交审核（提交按钮常驻，文案改为「提交更新审核」）。
class WorkPublishTab extends ConsumerStatefulWidget {
  const WorkPublishTab({super.key, required this.workId, required this.detail});

  final int workId;
  final AuthorWorkDetail detail;

  @override
  ConsumerState<WorkPublishTab> createState() => _WorkPublishTabState();
}

class _WorkPublishTabState extends ConsumerState<WorkPublishTab> {
  bool _submitting = false;

  Future<void> _submitReview() async {
    final work = widget.detail.work;
    if (widget.detail.chapters.isEmpty) {
      _toast('请先添加至少一章再提交审核');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提交审核'),
        content: Text('提交后《${work.title}》将进入审核流程，'
            '审核期间无法编辑章节。确定提交吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(authorWorkRepositoryProvider)
          .submitReview(widget.workId);
      ref.invalidate(authorWorkDetailProvider(widget.workId));
      ref.invalidate(authorReviewRecordsProvider(widget.workId));
      // 失效整个 family，覆盖 all/draft/reviewing/revision/rejected/published。
      ref.invalidate(myWorksProvider);
      if (!mounted) return;
      _toast('已提交审核');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('提交失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.detail.work;
    final editable = work.editable;
    final isPublished = work.status == 'published';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // 已发布作品的重新提交提示
        if (isPublished) ...[
          const _Notice(
            icon: Icons.info_outline,
            text: '作品已发布。修改章节或作品信息后，需重新提交审核以更新线上内容。',
          ),
          const SizedBox(height: 12),
        ],
        // 状态概览
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              _InfoRow(label: '作品状态', value: work.statusLabel),
              _InfoRow(
                  label: '章节数', value: '${widget.detail.chapters.length} 章'),
              _InfoRow(label: '总字数', value: '${work.wordCount} 字'),
            ],
          ),
        ),
        // 提交审核
        if (editable) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // 提交审核按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitReview,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isPublished ? '提交更新审核' : '提交审核'),
                  ),
                ),
              ],
            ),
          ),
        ],
        // 审核历史
        const SizedBox(height: 12),
        _ReviewHistorySection(workId: widget.workId),
        // 版本管理
        const SizedBox(height: 12),
        Material(
          color: AppColors.card,
          child: ListTile(
            leading:
                const Icon(Icons.history_outlined, color: AppColors.text2),
            title: const Text('版本管理'),
            subtitle: const Text('查看与创建作品版本'),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.text3),
            onTap: () => context
                .push(RoutePath.workVersionsUrl(widget.workId, title: work.title)),
          ),
        ),
      ],
    );
  }
}

/// 审核历史列表（A 套 GET /review-records）。
class _ReviewHistorySection extends ConsumerWidget {
  const _ReviewHistorySection({required this.workId});

  final int workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(authorReviewRecordsProvider(workId));
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('审核历史', style: TextStyle(color: AppColors.text2)),
          const SizedBox(height: 8),
          recordsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Text('审核记录加载失败',
                      style: TextStyle(color: AppColors.text3, fontSize: 13)),
                  // 失败态提供重试入口：失效对应 provider 触发重新拉取。
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(authorReviewRecordsProvider(workId)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
            data: (records) {
              if (records.isEmpty) {
                return const Text('尚未提交审核',
                    style:
                        TextStyle(color: AppColors.text3, fontSize: 13));
              }
              return Column(
                children: [
                  for (int i = 0; i < records.length; i++) ...[
                    _ReviewRecordTile(record: records[i]),
                    if (i < records.length - 1)
                      const Divider(
                          height: 0.5, color: AppColors.divider),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewRecordTile extends StatelessWidget {
  const _ReviewRecordTile({required this.record});

  final ReviewRecordItem record;

  @override
  Widget build(BuildContext context) {
    final hasOpinion =
        record.reviewOpinion != null && record.reviewOpinion!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ReviewStatusBadge(status: record.status),
              const SizedBox(width: 8),
              if (record.createdAt != null)
                Text(
                  record.createdAt!,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.text3),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasOpinion ? record.reviewOpinion! : '暂无审核意见',
            style: TextStyle(
              color: hasOpinion ? AppColors.text1 : AppColors.text3,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewStatusBadge extends StatelessWidget {
  const _ReviewStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'pending' || 'ai_reviewing' => AppColors.warning,
      'approved' => AppColors.success,
      'revision' || 'rejected' => AppColors.danger,
      _ => AppColors.text3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        reviewStatusLabel(status),
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
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
        border: Border(
            bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child:
                Text(label, style: const TextStyle(color: AppColors.text2)),
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

/// 顶部提示条（用于已发布作品的重新提交说明）。
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.warning.withOpacity(0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: AppColors.text2)),
          ),
        ],
      ),
    );
  }
}


