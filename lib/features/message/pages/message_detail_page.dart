import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 消息详情（规格 §8.6，契约 §1.5）。
///
/// 进入即标记已读（幂等）；标记失败不回滚展示，用户仍可看到正文。
class MessageDetailPage extends ConsumerStatefulWidget {
  const MessageDetailPage({super.key, required this.messageId});

  final int messageId;

  @override
  ConsumerState<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends ConsumerState<MessageDetailPage> {
  MessageItem? _message;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.messageId <= 0) {
      setState(() {
        _loading = false;
        _error = '消息不存在或已删除';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(messageRepositoryProvider);
      final message = await repo.detail(widget.messageId);
      // 详情即已读：失败不阻断阅读
      if (!message.read) {
        try {
          await repo.markRead(widget.messageId);
          ref.invalidate(unreadCountProvider);
        } catch (_) {
          // 已读失败仅影响角标，正文照常展示
        }
      }
      if (!mounted) return;
      setState(() {
        _message = message;
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
    return UserCenterScaffold(
        title: '消息详情',
        actions: null,
        body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView(message: '加载中');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final message = _message;
    if (message == null) return const EmptyView(message: '消息不存在');
    return SingleChildScrollView(
      child: Container(
        color: AppColors.card,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserStatusChip(text: message.typeLabel, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              message.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            if (message.createdAt != null) ...[
              const SizedBox(height: 6),
              Text(
                message.createdAt!,
                style: const TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              message.content ?? message.summary,
              style: const TextStyle(fontSize: 15, color: AppColors.text1, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
