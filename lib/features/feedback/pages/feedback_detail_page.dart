import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_widgets.dart';

/// 反馈详情（规格 §8.7，契约 §1.6）。
///
/// 展示状态、原文、管理员回复与处理时间；附件只在此详情返回。
/// 归属校验在服务端完成，他人反馈与不存在的反馈都返回 404。
class FeedbackDetailPage extends ConsumerStatefulWidget {
  const FeedbackDetailPage({super.key, required this.feedbackId});

  final int feedbackId;

  @override
  ConsumerState<FeedbackDetailPage> createState() => _FeedbackDetailPageState();
}

class _FeedbackDetailPageState extends ConsumerState<FeedbackDetailPage> {
  FeedbackItem? _item;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.feedbackId <= 0) {
      setState(() {
        _loading = false;
        _error = '反馈不存在';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await ref.read(feedbackRepositoryProvider).detail(widget.feedbackId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败，请稍后重试';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('反馈详情')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView(message: '加载中');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final item = _item;
    if (item == null) return const EmptyView(message: '反馈不存在');
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        UserCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserStatusChip(text: item.categoryLabel, color: AppColors.primary),
                      const SizedBox(width: 8),
                      UserStatusChip(text: item.status.label, color: _statusColor(item.status)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.content,
                    style: const TextStyle(fontSize: 15, color: AppColors.text1, height: 1.6),
                  ),
                  if (item.attachments.isNotEmpty) ...[
                    const Divider(height: 32, color: AppColors.divider),
                    const Text('附件', style: TextStyle(color: AppColors.text2, fontSize: 13)),
                    const SizedBox(height: 6),
                    for (final attachment in item.attachments)
                      Text(
                        attachment,
                        style: const TextStyle(fontSize: 12, color: AppColors.text3),
                      ),
                  ],
                  const Divider(height: 32, color: AppColors.divider),
                  if (item.submittedAt != null)
                    UserInfoLine(label: '提交时间', value: item.submittedAt!),
                  if (item.handledAt != null) UserInfoLine(label: '处理时间', value: item.handledAt!),
                ],
              ),
            ),
          ],
        ),
        if (item.reply != null && item.reply!.isNotEmpty) ...[
          const SizedBox(height: 12),
          UserCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '官方回复',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.reply!,
                      style: const TextStyle(fontSize: 14, color: AppColors.text2, height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Color _statusColor(FeedbackStatus status) {
    switch (status) {
      case FeedbackStatus.submitted:
        return AppColors.text3;
      case FeedbackStatus.processing:
        return AppColors.warning;
      case FeedbackStatus.replied:
        return AppColors.success;
      case FeedbackStatus.closed:
        return AppColors.text3;
    }
  }
}
