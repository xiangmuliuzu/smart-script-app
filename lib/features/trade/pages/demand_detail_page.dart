import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';
import '../widgets/demand_sandbox_pay_dialog.dart';
import '../widgets/demand_stage_panel.dart';

/// 任务详情页（接单制：展示需求 + 抢单/交付/验收）。
class DemandDetailPage extends ConsumerStatefulWidget {
  const DemandDetailPage({super.key, required this.demandId});
  final int demandId;

  @override
  ConsumerState<DemandDetailPage> createState() => _DemandDetailPageState();
}

class _DemandDetailPageState extends ConsumerState<DemandDetailPage> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final asyncTask = ref.watch(demandDetailProvider(widget.demandId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('任务详情'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: asyncTask.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: '加载失败：$e'),
        data: (task) => _buildContent(task),
      ),
    );
  }

  Widget _buildContent(DemandTask task) {
    final budgetYuan = task.budget != null ? (task.budget! / 100).toStringAsFixed(2) : '-';
    final myId = ref.watch(authControllerProvider).user?.userId;
    final isBuyer = myId != null && myId == task.clientId;
    final isClaimer = myId != null && task.acceptedCreatorId != null && myId == task.acceptedCreatorId;
    final inProgress = task.status == 'in_progress';
    final hasStages = task.totalEpisodes != null && task.totalEpisodes! > 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 标题 + 状态
        Row(
          children: [
            Expanded(
              child: Text(task.title ?? '',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            _chip(task.status),
          ],
        ),
        const SizedBox(height: 12),
        // 基本信息卡片
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _infoRow('任务编号', task.demandNo ?? '-'),
                _infoRow('预算', '$budgetYuan 元'),
                _infoRow('发布日期', _fmtDate(task.deadline)),
                if (hasStages)
                  _infoRow('验收轮次', '分 ${task.totalEpisodes} 集逐轮验收')
                else
                  _infoRow('完成时限', formatDurationHours(task.durationHours ?? 0)),
                _infoRow('托管状态', DemandEscrowStatus.label(task.escrowStatus)),
                _infoRow('托管额', '¥${task.escrowYuanText}'),
                if (task.depositStatus != null && task.depositStatus != DemandDepositStatus.none) ...[
                  _infoRow('押金状态', DemandDepositStatus.label(task.depositStatus)),
                  _infoRow('押金', '¥${task.depositYuanText}'),
                ],
                if (task.status == 'failed' && task.failReason != null)
                  _infoRow('失败原因', task.failReason!, valueColor: Colors.red),
                _infoRow('发布者', task.clientName ?? '-'),
                if (task.acceptedCreatorName != null || task.acceptedCreatorId != null)
                  _infoRow('接单人', task.acceptedCreatorName ?? '#${task.acceptedCreatorId}'),
                if (task.acceptedAt != null)
                  _infoRow('接单时间', _fmtDateTime(task.acceptedAt)),
                if (task.dueAt != null)
                  _infoRow('应完成时间', _fmtDateTime(task.dueAt)),
                if (task.isOverdue == 1)
                  _infoRow('逾期', '已逾期', valueColor: Colors.red),
                if (task.tags != null && task.tags!.isNotEmpty)
                  _infoRow('标签', task.tags!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 需求描述
        if (task.requirement != null && task.requirement!.isNotEmpty) ...[
          const Text('需求描述', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(task.requirement!, style: const TextStyle(fontSize: 14, height: 1.6)),
          ),
          const SizedBox(height: 16),
        ],
        // 任务会话入口（发布者 ↔ 创作者）
        if (myId != null && !isBuyer)
          _chatEntryButton(
            label: '联系发布者',
            onTap: () => _openDemandChat(task),
          ),
        if (myId != null && isBuyer && task.acceptedCreatorId != null)
          _chatEntryButton(
            label: '联系接单人',
            onTap: () => _openDemandChat(task, targetUserId: task.acceptedCreatorId),
          ),
        // 操作区（接单制 + 逐轮托管押金）
        if (task.status == 'open') ...[
          if (isBuyer && task.isEscrowPending) ...[
            _primaryActionButton(
              icon: Icons.check_circle_outline,
              label: '点一下完成托管 ¥${task.escrowYuanText}',
              loadingLabel: '处理中...',
              onSubmitting: _submitting,
              onTap: () => _devPassEscrow(task),
            ),
            const SizedBox(height: 2),
            // 正式扫码收款接口（保留给队友接入支付宝沙箱）
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _submitting ? null : () => _payEscrow(task),
                child: const Text('改用支付宝沙箱扫码付款',
                    style: TextStyle(color: AppColors.text3, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.push(RoutePath.demandPostEditUrl(task.demandId!)),
                child: const Text('编辑任务', style: TextStyle(color: AppColors.primary)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _confirmClose(task),
                child: const Text('关闭任务', style: TextStyle(color: Colors.red)),
              ),
            ),
          ] else if (isBuyer) ...[
            _escrowPaidBanner(),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _confirmClose(task),
                child: const Text('关闭任务', style: TextStyle(color: Colors.red)),
              ),
            ),
          ] else if (task.isEscrowed) ...[
            _primaryActionButton(
              icon: Icons.check_circle_outline,
              // 与发布者“点一下完成托管”同口径：直通付款接单；未接单前库里 deposit_amount 默认 0，固定按总价 10% 预览
              label: '支付押金 ¥${_depositYuanPreview(task)}',
              loadingLabel: '处理中...',
              onSubmitting: _submitting,
              onTap: () => _devPassDeposit(task),
            ),
            const SizedBox(height: 2),
            // 正式扫码收款接口（保留给队友接入支付宝沙箱）
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _submitting ? null : () => _payDeposit(task),
                child: const Text('改用支付宝沙箱扫码付款',
                    style: TextStyle(color: AppColors.text3, fontSize: 12)),
              ),
            ),
          ] else
            _hintBar('该任务尚未完成托管付款，暂不可接单'),
        ],
        // 进行中的倒计时（任务双方均可见：发布者也要看到剩余时限与“计时已暂停”，否则无从判断要不要延时）
        if (inProgress && (isBuyer || isClaimer)) _buildCountdown(task),
        // 验收面板（已配置轮次且接单后/完成时可见）
        if (hasStages && (inProgress || task.status == 'completed')) ...[
          const SizedBox(height: 8),
          DemandStagePanel(demandId: task.demandId!, isBuyer: isBuyer),
        ],
      ],
    );
  }

  /// 发布者一键直通完成托管（沙箱未接入时的开发放行）。
  Future<void> _devPassEscrow(DemandTask task) async {
    setState(() => _submitting = true);
    try {
      await ref.read(demandRepositoryProvider).devPassEscrow(task.demandId!);
      ref.invalidate(demandDetailProvider(widget.demandId));
      ref.invalidate(demandStatsProvider); // 直通托管后广场可接单数/奖金池变化
      if (mounted) showAppToast(context, '托管已到账，任务已对外发布');
    } catch (e) {
      if (mounted) showAppToast(context, '完成托管失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 发布者发起托管付款：拿二维码 → 弹窗扫码 → 查单确认（支付宝沙箱，保留给队友接入）。
  Future<void> _payEscrow(DemandTask task) async {
    setState(() => _submitting = true);
    try {
      final data = await ref.read(demandRepositoryProvider).payEscrow(task.demandId!);
      if (!mounted) return;
      final paid = await showDialog<bool>(
        context: context,
        builder: (_) => DemandSandboxPayDialog(
          title: '支付托管款',
          qrCode: data['qrCode'] as String,
          amountYuanText: task.escrowYuanText,
          hint: '将预算全额付入平台第三方托管账户（沙箱收款，不产生真实资金）。托管完成后任务才对外可接单。',
          confirm: () async => <String, dynamic>{
              'paid': await ref.read(demandRepositoryProvider).confirmEscrow(task.demandId!),
            },
        ),
      );
      if (paid == true) {
        ref.invalidate(demandDetailProvider(widget.demandId));
        ref.invalidate(demandStatsProvider); // 托管到账后任务对外可接单
        if (mounted) showAppToast(context, '托管已到账，任务已发布');
      }
    } catch (e) {
      if (mounted) showAppToast(context, '发起托管付款失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 创作者点一下完成押金付款并接单（开发直通，与发布者托管直通同开关同口径）。
  Future<void> _devPassDeposit(DemandTask task) async {
    setState(() => _submitting = true);
    try {
      await ref.read(demandRepositoryProvider).devPassDeposit(task.demandId!);
      ref.invalidate(demandDetailProvider(widget.demandId));
      ref.invalidate(demandStagesProvider(widget.demandId));
      ref.invalidate(demandStatsProvider); // 接单后任务脱离可接单集合
      if (mounted) showAppToast(context, '押金已支付，接单成功');
    } catch (e) {
      if (mounted) showAppToast(context, '支付押金失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 创作者付押金即接单：拿押金二维码 → 扫码 → 查单确认（服务端自动接单）。
  Future<void> _payDeposit(DemandTask task) async {
    setState(() => _submitting = true);
    try {
      final data = await ref.read(demandRepositoryProvider).payDeposit(task.demandId!);
      if (!mounted) return;
      final amountFen = (data['amount'] as num?)?.toInt();
      final amountYuan = amountFen != null ? (amountFen / 100).toStringAsFixed(2) : _depositYuanPreview(task);
      final paid = await showDialog<bool>(
        context: context,
        builder: (_) => DemandSandboxPayDialog(
          title: '支付押金',
          qrCode: data['qrCode'] as String,
          amountYuanText: amountYuan,
          hint: '支付押金即视为接单成功（沙箱收款）。逾期未验收通过，押金将被没收。',
          confirm: () => ref.read(demandRepositoryProvider).confirmDeposit(task.demandId!),
        ),
      );
      if (paid == true) {
        ref.invalidate(demandDetailProvider(widget.demandId));
        ref.invalidate(demandStagesProvider(widget.demandId));
        ref.invalidate(demandStatsProvider); // 接单后任务脱离可接单集合
        if (mounted) showAppToast(context, '押金已入账，接单成功');
      } else {
        // 未成交：可能是任务已被他人抢先接走（弹窗展示 reason），刷新详情同步最新状态
        ref.invalidate(demandDetailProvider(widget.demandId));
        ref.invalidate(demandStatsProvider);
      }
    } catch (e) {
      if (mounted) showAppToast(context, '发起押金付款失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 提取可读错误文案：业务异常取后端 message（如“请先开通创作者资格再接单”），其余回退默认。
  String _errText(Object e) => e is ApiException && e.message.isNotEmpty ? e.message : '请稍后重试';

  /// 押金预览（预算的10%、向下取整到分）。
  String _depositYuanPreview(DemandTask task) {
    final budgetFen = task.budget;
    if (budgetFen == null || budgetFen <= 0) return '0.00';
    final depositFen = (budgetFen / 10).floor();
    return (depositFen / 100).toStringAsFixed(2);
  }

  Widget _primaryActionButton({
    required IconData icon,
    required String label,
    required String loadingLabel,
    required bool onSubmitting,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onSubmitting ? null : onTap,
        icon: Icon(icon),
        label: Text(onsubmittingGuard(loadingLabel, label)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  String onsubmittingGuard(String loadingLabel, String label) =>
      _submitting ? loadingLabel : label;

  Widget _escrowPaidBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified, size: 18, color: Colors.green),
          SizedBox(width: 8),
          Expanded(
            child: Text('托管已到账，等待创作者付押金接单', style: TextStyle(fontSize: 13, color: Colors.green)),
          ),
        ],
      ),
    );
  }

  Widget _hintBar(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: Colors.orange.shade800)),
    );
  }

  Widget _buildCountdown(DemandTask task) => DemandCountdownBar(task: task);

  Future<void> _confirmClose(DemandTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认关闭'),
        content: const Text('关闭后将不再接受新的抢单，确定吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(demandRepositoryProvider).closeDemand(task.demandId!);
        ref.invalidate(demandDetailProvider(widget.demandId));
        ref.invalidate(demandStatsProvider); // 关闭后任务脱离可接单集合
        if (mounted) showAppToast(context, '已关闭');
      } catch (e) {
        if (mounted) showAppToast(context, '操作失败：${_errText(e)}');
      }
    }
  }

  /// 任务会话入口按钮（发布者 ↔ 创作者）。
  Widget _chatEntryButton({required String label, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _submitting ? null : onTap,
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text(_submitting ? '发起中...' : label),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
        ),
      ),
    );
  }

  /// 发起/获取任务会话并跳转聊天详情。[targetUserId] 为发布者发起时指定的创作者。
  Future<void> _openDemandChat(DemandTask task, {int? targetUserId}) async {
    final demandId = task.demandId;
    if (demandId == null) return;
    setState(() => _submitting = true);
    try {
      final sessionId = await ref
          .read(demandRepositoryProvider)
          .createDemandChatSession(demandId, targetUserId: targetUserId);
      if (!mounted) return;
      setState(() => _submitting = false);
      context.push(RoutePath.chatDetail(sessionId));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(context, '发起会话失败：${_errText(e)}');
    }
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: valueColor))),
        ],
      ),
    );
  }

  Widget _chip(String? status) {
    Color color;
    switch (status) {
      case 'open': color = Colors.green;
      case 'in_progress': color = Colors.blue;
      case 'completed': color = AppColors.primary;
      case 'selected': color = AppColors.primary;
      case 'failed': color = Colors.red;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(_statusLabel(status),
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    );
  }

  static String _statusLabel(String? status) {
    switch (status) {
      case 'open': return '待接单';
      case 'in_progress': return '进行中';
      case 'completed': return '已完成';
      case 'selected': return '已选定';
      case 'closed': return '已关闭';
      case 'failed': return '已失败';
      default: return status ?? '未知';
    }
  }

  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '-';
    return '${_fmtDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 进行中倒计时条：只展示当前活动轮的剩余时间（后续轮次时限见下方验收面板）。
/// 自带 30s 周期重绘，使“剩余 X 小时 Y 分”实时走动。
class DemandCountdownBar extends ConsumerStatefulWidget {
  const DemandCountdownBar({super.key, required this.task});
  final DemandTask task;

  @override
  ConsumerState<DemandCountdownBar> createState() => _DemandCountdownBarState();
}

class _DemandCountdownBarState extends ConsumerState<DemandCountdownBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.task.dueAt != null && widget.task.isOverdue != 1) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final stages =
        ref.watch(demandStagesProvider(task.demandId!)).valueOrNull ?? const <DemandStage>[];
    // 当前活动轮：已激活且未通过（剩余时间按本轮截止计算，非整单）
    DemandStage? active;
    for (final s in stages) {
      if (s.startedAt != null && s.status != 'approved') {
        active = s;
        break;
      }
    }
    // 后续轮次时限不在倒计时条展示，由下方验收面板逐轮列出
    final due = active?.dueAt ?? task.dueAt;
    String text;
    Color color;
    if (active != null && active.isPausedForReview) {
      // 审核期间（AI审核中/待人工验收）计时暂停，不走剩余时间倒计时
      text = active.isAiReviewing ? 'AI审核中，计时已暂停' : '验收中，计时已暂停';
      color = active.isAiReviewing ? Colors.purple : Colors.blue;
    } else if (active != null && active.hasPendingExtend) {
      // 待处理的延时申请同样暂停超时判定（与后端 refreshRoundState 同口径）
      text = '延时申请待处理，计时已暂停';
      color = Colors.orange;
    } else if (task.isOverdue == 1 || (due != null && due.isBefore(DateTime.now()))) {
      text = '已逾期，请尽快处理';
      color = Colors.red;
    } else if (due == null) {
      text = '进行中';
      color = Colors.blue;
    } else {
      final remain = due.difference(DateTime.now());
      final h = remain.inHours;
      final m = remain.inMinutes % 60;
      text = '剩余 $h 小时 $m 分';
      color = h < 24 ? Colors.orange : Colors.blue;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              active != null ? '第${active.stageOrder}轮 · $text' : text,
              style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
