import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../data/promotion_models.dart';
import '../data/promotion_providers.dart';
import '../widgets/promotion_widgets.dart';

/// 推广详情：状态说明、作品与投放信息、取消 / 去支付。
class PromotionDetailPage extends ConsumerStatefulWidget {
  const PromotionDetailPage({super.key, required this.applyId});

  final int applyId;

  @override
  ConsumerState<PromotionDetailPage> createState() =>
      _PromotionDetailPageState();
}

class _PromotionDetailPageState extends ConsumerState<PromotionDetailPage> {
  /// 锁坑倒计时每秒刷新（剩余时间按 lockExpireAt 实时计算）。
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(promotionDetailProvider(widget.applyId));

    return Scaffold(
      appBar: AppBar(title: const Text('推广详情')),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(message: '加载推广详情…'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载推广详情失败',
          onRetry: () =>
              ref.invalidate(promotionDetailProvider(widget.applyId)),
        ),
        data: (application) => _buildBody(context, ref, application),
      ),
      bottomNavigationBar: async.valueOrNull == null
          ? null
          : _buildBottomBar(context, ref, async.valueOrNull!),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    PromotionApplication application,
  ) {
    final statusColor = promotionStatusColor(application);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        application.displayStatus,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    PromotionStatusChip(
                      label: application.slotLabel,
                      color: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _statusHint(application),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text2,
                    height: 1.5,
                  ),
                ),
                if (application.canPay &&
                    application.lockRemainText != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '锁坑剩余 ${application.lockRemainText}，超时将自动释放位次',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.accent,
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
        AppCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                WorkCover(
                  url: application.workCover ?? '',
                  title: application.workTitle,
                  width: 58,
                  height: 78,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application.workTitle.isEmpty
                            ? '未命名作品'
                            : application.workTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        application.authorName.isEmpty
                            ? application.sourceLabel
                            : '${application.authorName} · ${application.sourceLabel}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (application.slotType == 'banner' &&
            (application.materialUrl ?? '').isNotEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '轮播素材',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        AppConfig.resolveAssetUrl(application.materialUrl!),
                        fit: BoxFit.cover,
                        cacheWidth: 1080,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.fill,
                          alignment: Alignment.center,
                          child: const Text(
                            '素材预览失败',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.text3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              children: [
                _InfoRow(
                  label: '申请单号',
                  value: application.applyNo.isEmpty
                      ? '${application.applyId}'
                      : application.applyNo,
                ),
                _InfoRow(label: '投放资源位', value: application.slotLabel),
                _InfoRow(label: '投放天数', value: '${application.days} 天'),
                _InfoRow(
                  label: '投放时段',
                  value:
                      '${application.startTime ?? '—'} ~ ${application.endTime ?? '—'}',
                ),
                _InfoRow(
                  label: '申请时间',
                  value: application.createTime ?? '—',
                ),
                if (application.payTime != null)
                  _InfoRow(label: '支付时间', value: application.payTime!),
                const Divider(height: 16, color: AppColors.divider),
                _InfoRow(
                  label: '订单金额',
                  value: '¥${formatPromotionMoney(application.amount)}',
                  valueColor: AppColors.accent,
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        if (application.rejectReason != null &&
            application.rejectReason!.isNotEmpty)
          AppCard(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF0EE),
                borderRadius: BorderRadius.circular(AppRadius.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '驳回原因',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    application.rejectReason!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text2,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget? _buildBottomBar(
    BuildContext context,
    WidgetRef ref,
    PromotionApplication application,
  ) {
    if (!application.canCancel && !application.canPay) return null;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: Color(0x14183A6E),
            offset: Offset(0, -2),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            if (application.canCancel)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _cancel(context, ref, application),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: AppColors.text2,
                    side: const BorderSide(color: AppColors.divider),
                  ),
                  child: const Text('取消申请'),
                ),
              ),
            if (application.canCancel && application.canPay)
              const SizedBox(width: 10),
            if (application.canPay)
              Expanded(
                child: FilledButton(
                  onPressed: () => _pay(context, ref),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: AppColors.accent,
                  ),
                  child: const Text('去支付'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    await context.push<bool>(RoutePath.promotionPayUrl(widget.applyId));
    ref.invalidate(promotionDetailProvider(widget.applyId));
    ref.invalidate(myPromotionsProvider);
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    PromotionApplication application,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消推广申请'),
        content: Text(
          application.status == 'pending'
              ? '取消后该申请将关闭，确定取消吗？'
              : '取消后已锁定的位次会立即释放，确定取消吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:
                const Text('确定取消', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(promotionRepositoryProvider).cancel(application.applyId);
      ref.invalidate(myPromotionsProvider);
      ref.invalidate(promotionDetailProvider(widget.applyId));
      if (!context.mounted) return;
      showAppToast(context, '已取消推广申请');
    } catch (error) {
      if (!context.mounted) return;
      showAppToast(
        context,
        error is ApiException ? error.message : '取消失败，请稍后重试',
      );
    }
  }

  String _statusHint(PromotionApplication application) {
    switch (application.displayStatus) {
      case '待审核':
        return '申请已提交，平台审核通过后会为你锁定该位次，请耐心等待。';
      case '待支付':
        return '审核已通过，请在锁坑倒计时内完成支付；超时后位次将自动释放。';
      case '待生效':
        return '支付已完成，将在开始时间自动生效，请留意投放时段。';
      case '投放中':
        return '推广正在投放中，后台会按投放时段自动结束，无需手动操作。';
      case '已结束':
        return '本次推广已结束，如需继续曝光可重新发起推广。';
      case '已驳回':
        return '申请未通过审核，可根据驳回原因调整后重新申请。';
      case '已取消':
        return '本次推广申请已取消。';
      case '已失效':
        return '支付超时，锁定的位次已释放，可重新发起推广。';
      default:
        return '推广状态更新中。';
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor = AppColors.text1,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: AppColors.text3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                color: valueColor,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
