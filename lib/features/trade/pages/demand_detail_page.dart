import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/demand_task_type.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';
import '../widgets/demand_stage_panel.dart';

/// 任务详情页（平台发布 → 创作者先到先得接单 → 逐轮交付）。
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
    // 游客与登录用户拿到的是两份不同视图（后端对游客做字段白名单，接单人等私密字段不在其中）。
    // 登录态一变，缓存的游客视图必须重取，否则本人回到详情页会因为拿不到最新字段而看不到接单入口。
    ref.listen(authControllerProvider, (prev, next) {
      if (prev?.user?.userId != next.user?.userId) {
        ref.invalidate(demandDetailProvider(widget.demandId));
      }
    });
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
            _typeChip(task.taskType),
            const SizedBox(width: 6),
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
                _infoRow('任务类型', DemandTaskType.labelOf(task.taskType)),
                _infoRow('预算', '$budgetYuan 元'),
                _infoRow('截止日期', _fmtDate(task.deadline)),
                if (hasStages)
                  _infoRow('验收轮次', _roundsText(task))
                else
                  _infoRow('完成时限', formatDurationHours(task.durationHours ?? 0)),
                _infoRow('交付要求', DemandTaskType.deliverHintOf(task.taskType)),
                if (task.status == 'failed' && task.failReason != null)
                  _infoRow('失败原因', task.failReason!, valueColor: Colors.red),
                _infoRow('需求方', task.clientName ?? '-'),
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
        // 源剧本（分镜类任务）：接单方靠它评估工作量
        if (DemandTaskType.isStoryboard(task.taskType)) ...[
          _buildSourceScriptBlock(task, isLoggedIn: myId != null),
          const SizedBox(height: 16),
        ],
        // 任务会话入口（创作者 ↔ 平台运营）
        if (myId != null && isClaimer)
          _chatEntryButton(
            label: '联系平台',
            onTap: () => _openDemandChat(task),
          ),
        // 操作区：平台已托管预算，创作者先到先得直接接单
        if (task.status == 'open') ...[
          _primaryActionButton(
            icon: Icons.gavel,
            label: '我要接单',
            loadingLabel: '接单中...',
            onSubmitting: _submitting,
            onTap: () {
              if (_ensureLoginForAction(task)) _claim(task);
            },
          ),
          const SizedBox(height: 2),
          _hintBar('接单后按轮次交付，每轮通过验收即结算该轮款项。'),
        ],
        // 进行中的倒计时（仅接单人可见：后续验收与延时已收归平台运营）
        if (inProgress && isClaimer) _buildCountdown(task),
        // 验收面板（已配置轮次且接单后/完成时可见；仅接单人可见）
        if (hasStages && (inProgress || task.status == 'completed') && isClaimer) ...[
          const SizedBox(height: 8),
          DemandStagePanel(demandId: task.demandId!),
        ],
      ],
    );
  }

  /// 创作者抢单（先到先得，无需押金）。落败/资格不足由后端 message 说明。
  Future<void> _claim(DemandTask task) async {
    setState(() => _submitting = true);
    try {
      await ref.read(demandRepositoryProvider).claimDemand(task.demandId!);
      ref.invalidate(demandDetailProvider(widget.demandId));
      ref.invalidate(demandStagesProvider(widget.demandId));
      ref.invalidate(demandStatsProvider); // 接单后任务脱离可接单集合
      if (mounted) showAppToast(context, '接单成功，请按首轮时限交付');
    } catch (e) {
      if (mounted) showAppToast(context, '接单失败：${_errText(e)}');
      ref.invalidate(demandDetailProvider(widget.demandId));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 提取可读错误文案：业务异常取后端 message（如“请先开通创作者资格再接单”），其余回退默认。
  String _errText(Object e) => e is ApiException && e.message.isNotEmpty ? e.message : '请稍后重试';

  /// 接单相关动作一律先过登录守卫：游客直调受保护接口会拿到 401，
  /// 而 ApiClient 把任何 401 当会话过期处理，会把人从详情页踢走。
  bool _ensureLoginForAction(DemandTask task) => AuthGuard.requireLogin(
        context,
        ref,
        target: RoutePath.demandDetailUrl(task.demandId ?? widget.demandId),
      );

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

  /// 任务会话入口按钮（创作者 ↔ 平台运营）。
  Widget _chatEntryButton({required String label, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _submitting ? null : onTap,
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text(_submitting ? '发起中...' : label),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.text1),
        ),
      ),
    );
  }

  /// 发起/获取任务会话（创作者侧：与接单任务的平台运营沟通）并跳转聊天详情。
  Future<void> _openDemandChat(DemandTask task) async {
    final demandId = task.demandId;
    if (demandId == null) return;
    setState(() => _submitting = true);
    try {
      final sessionId = await ref
          .read(demandRepositoryProvider)
          .createDemandChatSession(demandId);
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

  /// 验收轮次文案随类型分化：分镜类是对源剧本出分镜，不是逐轮交剧本稿。
  String _roundsText(DemandTask task) {
    final n = task.totalEpisodes;
    switch (DemandTaskType.normalize(task.taskType)) {
      case DemandTaskType.storyboard:
        return '按源剧本分 $n 集逐轮交付分镜';
      case DemandTaskType.scriptStoryboard:
        return '分 $n 集逐轮交付剧本与分镜';
      default:
        return '分 $n 集逐轮验收';
    }
  }

  /// 源剧本区块：给出关联作品/上传文件的现状，并入口到全本查阅页。
  Widget _buildSourceScriptBlock(DemandTask task, {required bool isLoggedIn}) {
    final hasWork = (task.sourceWorkTitle ?? '').isNotEmpty;
    // 游客视图不带 sourceScriptUrl（后端白名单），只认文件名，否则会误报「尚未提供源剧本」
    final hasFile =
        (task.sourceScriptUrl ?? '').isNotEmpty || (task.sourceScriptName ?? '').isNotEmpty;
    final accent = DemandTaskType.colorOf(task.taskType);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('源剧本',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accent)),
          const SizedBox(height: 6),
          if (!hasWork && !hasFile)
            Text(
              isLoggedIn
                  ? '平台尚未提供源剧本（可能已失效），请联系平台补充后再接单。'
                  : '登录后可查看平台提供的源剧本。',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: Colors.red.shade600))
          else
            Text(
              [
                if (hasWork) '关联作品《${task.sourceWorkTitle}》',
                if (hasFile) '剧本文件：${(task.sourceScriptName ?? '').isNotEmpty ? task.sourceScriptName : "未命名文件"}',
              ].join(' · '),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          if (hasWork || hasFile) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => AuthGuard.pushProtected(
                  context,
                  ref,
                  target: RoutePath.demandSourceScriptUrl(task.demandId!),
                ),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('查看源剧本'),
                style: OutlinedButton.styleFrom(foregroundColor: accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeChip(String? taskType) {
    final color = DemandTaskType.colorOf(taskType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(DemandTaskType.labelOf(taskType),
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _chip(String? status) {
    Color color;
    switch (status) {
      case 'open': color = Colors.green;
      case 'in_progress': color = AppColors.text2;
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
      color = active.isAiReviewing ? Colors.purple : AppColors.text2;
    } else if (active != null && active.hasPendingExtend) {
      // 待处理的延时申请同样暂停超时判定（与后端 refreshRoundState 同口径）
      text = '延时申请待处理，计时已暂停';
      color = Colors.orange;
    } else if (task.isOverdue == 1 || (due != null && due.isBefore(DateTime.now()))) {
      text = '已逾期，请尽快处理';
      color = Colors.red;
    } else if (due == null) {
      text = '进行中';
      color = AppColors.text2;
    } else {
      final remain = due.difference(DateTime.now());
      final h = remain.inHours;
      final m = remain.inMinutes % 60;
      text = '剩余 $h 小时 $m 分';
      color = h < 24 ? Colors.orange : AppColors.text2;
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
