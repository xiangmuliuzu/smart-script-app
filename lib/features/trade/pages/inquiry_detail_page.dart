import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 询盘详情页（分工条目 5/6）
///
/// 展示询盘内容、作品信息、双方信息、当前状态；
/// 卖方视角可执行接受/拒绝操作，买方视角可关闭询盘。
class InquiryDetailPage extends ConsumerStatefulWidget {
  const InquiryDetailPage({super.key, required this.inquiryId});

  final int inquiryId;

  @override
  ConsumerState<InquiryDetailPage> createState() => _InquiryDetailPageState();
}

class _InquiryDetailPageState extends ConsumerState<InquiryDetailPage> {
  bool _operating = false;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(inquiryDetailProvider(widget.inquiryId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('询盘详情'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: detailAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: '加载失败: $e',
          onRetry: () => ref.invalidate(inquiryDetailProvider(widget.inquiryId)),
        ),
        data: (inquiry) => _buildContent(inquiry),
      ),
    );
  }

  Widget _buildContent(Inquiry inquiry) {
    // 判断当前用户角色（简化：根据 buyerId 判断）
    // 实际应从 auth provider 获取当前用户 ID
    final isBuyer = true; // 默认当前用户是买方，实际需从 auth 获取

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 状态卡片
                _buildStatusCard(inquiry),
                const SizedBox(height: 16),

                // 作品信息
                _buildSectionTitle('作品信息'),
                const SizedBox(height: 8),
                _buildWorkCard(inquiry),
                const SizedBox(height: 16),

                // 询盘内容
                _buildSectionTitle('询盘内容'),
                const SizedBox(height: 8),
                _buildInquiryInfo(inquiry),
                const SizedBox(height: 16),

                // 双方信息
                _buildSectionTitle('双方信息'),
                const SizedBox(height: 8),
                _buildPartyInfo(inquiry, isBuyer),
                const SizedBox(height: 16),

                // 留言
                if (inquiry.message != null && inquiry.message!.isNotEmpty) ...[
                  _buildSectionTitle('留言'),
                  const SizedBox(height: 8),
                  _buildMessageCard(inquiry.message!),
                ],
              ],
            ),
          ),
        ),

        // 底部操作栏
        _buildActionBar(inquiry, isBuyer),
      ],
    );
  }

  Widget _buildStatusCard(Inquiry inquiry) {
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (inquiry.status) {
      case InquiryStatus.pending:
        bgColor = AppColors.warning.withOpacity(0.1);
        textColor = AppColors.warning;
        icon = Icons.pending;
      case InquiryStatus.accepted:
        bgColor = AppColors.success.withOpacity(0.1);
        textColor = AppColors.success;
        icon = Icons.check_circle;
      case InquiryStatus.rejected:
        bgColor = AppColors.danger.withOpacity(0.1);
        textColor = AppColors.danger;
        icon = Icons.cancel;
      case InquiryStatus.deal:
        bgColor = AppColors.primary.withOpacity(0.1);
        textColor = AppColors.primary;
        icon = Icons.handshake;
      case InquiryStatus.closed:
        bgColor = AppColors.fill;
        textColor = AppColors.text3;
        icon = Icons.close;
      default:
        bgColor = AppColors.fill;
        textColor = AppColors.text2;
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  InquiryStatus.label(inquiry.status),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '询盘编号: ${inquiry.inquiryNo ?? '-'}',
                  style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.text1,
      ),
    );
  }

  Widget _buildWorkCard(Inquiry inquiry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.article, color: AppColors.text3, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inquiry.workTitle ?? '作品',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '作品ID: ${inquiry.workId}',
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInquiryInfo(Inquiry inquiry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _buildInfoRow('授权类型', LicenseType.label(inquiry.licenseType)),
          const Divider(height: 24),
          _buildInfoRow('预算金额', inquiry.budgetYuan),
          const Divider(height: 24),
          _buildInfoRow('创建时间', formatDateTime(inquiry.createdAt)),
          if (inquiry.expireAt != null) ...[
            const Divider(height: 24),
            _buildInfoRow('有效期至', formatDateTime(inquiry.expireAt)),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.text3),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 14, color: AppColors.text1),
        ),
      ],
    );
  }

  Widget _buildPartyInfo(Inquiry inquiry, bool isBuyer) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _buildPartyRow('买方', inquiry.buyerName ?? '-'),
          const Divider(height: 24),
          _buildPartyRow('卖方', inquiry.sellerName ?? '-'),
        ],
      ),
    );
  }

  Widget _buildPartyRow(String label, String name) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 14, color: AppColors.text1),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 14, color: AppColors.text2),
      ),
    );
  }

  Widget _buildActionBar(Inquiry inquiry, bool isBuyer) {
    // 只有 pending 状态可以操作
    if (inquiry.status != InquiryStatus.pending) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (isBuyer) ...[
              // 买方可以关闭
              Expanded(
                child: OutlinedButton(
                  onPressed: _operating ? null : () => _closeInquiry(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text2,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('关闭询盘'),
                ),
              ),
            ] else ...[
              // 卖方可以接受/拒绝
              Expanded(
                child: OutlinedButton(
                  onPressed: _operating ? null : () => _rejectInquiry(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('拒绝'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _operating ? null : () => _acceptInquiry(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('接受'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _acceptInquiry() async {
    setState(() => _operating = true);
    try {
      await ref.read(tradeRepositoryProvider).acceptInquiry(widget.inquiryId);
      if (mounted) {
        showAppToast(context, '已接受询盘');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '操作失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _operating = false);
      }
    }
  }

  Future<void> _rejectInquiry() async {
    setState(() => _operating = true);
    try {
      await ref.read(tradeRepositoryProvider).rejectInquiry(widget.inquiryId);
      if (mounted) {
        showAppToast(context, '已拒绝询盘');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '操作失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _operating = false);
      }
    }
  }

  Future<void> _closeInquiry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认关闭'),
        content: const Text('关闭后将无法恢复，确定要关闭这个询盘吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认关闭', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _operating = true);
    try {
      await ref.read(tradeRepositoryProvider).closeInquiry(widget.inquiryId);
      if (mounted) {
        showAppToast(context, '已关闭询盘');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '操作失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _operating = false);
      }
    }
  }
}
