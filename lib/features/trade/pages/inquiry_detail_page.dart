import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/data/chat_providers.dart';
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
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
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
    // 从 auth provider 获取当前用户ID
    final authState = ref.watch(authControllerProvider);
    final currentUserId = authState.user?.userId;

    // 根据当前用户ID与询盘中的 buyerId/sellerId 比对判断角色
    // 一个用户可以同时是买方和卖方，具体在某笔询盘中扮演哪个角色取决于ID比对
    final isBuyerInThisInquiry = inquiry.buyerId == currentUserId;
    final isSellerInThisInquiry = inquiry.sellerId == currentUserId;

    // 异常情况：当前用户既不是买方也不是卖方（不应发生，后端会拦截）
    if (!isBuyerInThisInquiry && !isSellerInThisInquiry) {
      return const ErrorView(message: '无权查看此询盘');
    }

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
                _buildPartyInfo(inquiry),
                const SizedBox(height: 16),

                // 留言
                if (inquiry.message != null && inquiry.message!.isNotEmpty) ...[
                  _buildSectionTitle('留言'),
                  const SizedBox(height: 8),
                  _buildMessageCard(inquiry.message!),
                  const SizedBox(height: 16),
                ],

                // 报价与议价
                _buildSectionTitle('报价与议价'),
                const SizedBox(height: 8),
                _buildQuoteSection(inquiry, isBuyerInThisInquiry, isSellerInThisInquiry),
              ],
            ),
          ),
        ),

        // 底部操作栏
        _buildActionBar(inquiry, isBuyerInThisInquiry, isSellerInThisInquiry),

        // 底部聊天按钮（始终显示）
        _buildChatBar(),
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

  Widget _buildPartyInfo(Inquiry inquiry) {
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

  /// 报价与议价区块
  Widget _buildQuoteSection(
    Inquiry inquiry,
    bool isBuyerInThisInquiry,
    bool isSellerInThisInquiry,
  ) {
    // 询盘必须被接受后才能报价
    final canQuote = inquiry.status == InquiryStatus.accepted ||
        inquiry.status == InquiryStatus.deal;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // 查看报价记录（双方都可见）
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                context.push(
                  '${RoutePath.quoteList}?inquiryId=${widget.inquiryId}&workTitle=${Uri.encodeComponent(inquiry.workTitle ?? '')}',
                );
              },
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text('查看报价记录'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 卖方可以提交报价
          if (isSellerInThisInquiry && canQuote)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await context.push<bool>(
                    '${RoutePath.quoteCreate}?inquiryId=${widget.inquiryId}&workTitle=${Uri.encodeComponent(inquiry.workTitle ?? '')}',
                  );
                  if (result == true) {
                    ref.invalidate(inquiryDetailProvider(widget.inquiryId));
                  }
                },
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('提交报价'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          // 买方可以发起议价
          if (isBuyerInThisInquiry && canQuote)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push(
                    '${RoutePath.quoteList}?inquiryId=${widget.inquiryId}&workTitle=${Uri.encodeComponent(inquiry.workTitle ?? '')}',
                  );
                },
                icon: const Icon(Icons.gavel, size: 18),
                label: const Text('发起议价'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          if (!canQuote)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('询盘被接受后可进行报价/议价', style: TextStyle(fontSize: 12, color: AppColors.text3)),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar(
    Inquiry inquiry,
    bool isBuyerInThisInquiry,
    bool isSellerInThisInquiry,
  ) {
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
            if (isBuyerInThisInquiry) ...[
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
            ],
            if (isSellerInThisInquiry) ...[
              // 卖方可以接受/拒绝
              if (isBuyerInThisInquiry) const SizedBox(width: 12),
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

  /// 底部聊天按钮栏（始终显示）
  Widget _buildChatBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _operating ? null : _startChat,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('联系对方'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
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

  /// 创建或获取 TRADE 类型聊天会话并跳转到聊天详情页
  Future<void> _startChat() async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final session = await chatRepo.createTradeSession(widget.inquiryId);
      if (mounted) {
        context.push(RoutePath.chatDetail(session.session.sessionId));
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '创建会话失败: $e');
      }
    }
  }
}
