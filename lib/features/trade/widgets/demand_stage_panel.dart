import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/app_toast.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';

/// 验收轮次面板：竖向时间线展示，支持创作者提交交付 / 买方审核操作。
class DemandStagePanel extends ConsumerStatefulWidget {
  final int demandId;
  /// 当前用户角色：true=买方(发布者)，false=创作者
  final bool isBuyer;

  const DemandStagePanel({
    super.key,
    required this.demandId,
    this.isBuyer = false,
  });

  @override
  ConsumerState<DemandStagePanel> createState() => _DemandStagePanelState();
}

class _DemandStagePanelState extends ConsumerState<DemandStagePanel> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // 延时审批与下一轮激活可能发生在对方端：定时重拉，截止时间/剩余时长自动同步
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      ref.invalidate(demandStagesProvider(widget.demandId));
      ref.invalidate(demandExtendHistoryProvider(widget.demandId));
      // 整单截止跟随轮次同步，避免详情页顶部还停在顺延前的时间
      ref.invalidate(demandDetailProvider(widget.demandId));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stagesAsync = ref.watch(demandStagesProvider(widget.demandId));

    return stagesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('加载验收轮次失败：$e',
            style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
      ),
      data: (stages) {
        if (stages.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('该任务未配置验收轮次',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          );
        }
        // 延时记录（申请延时 + 自主延时）：整单取一次，按轮分发到各条目（每条一行，不互相覆盖）
        final history =
            ref.watch(demandExtendHistoryProvider(widget.demandId)).valueOrNull ??
                const <DemandExtendApply>[];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('验收进度',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ...stages.map((s) => _StageTimelineItem(
                    stage: s,
                    demandId: widget.demandId,
                    isBuyer: widget.isBuyer,
                    extendApplies: history
                        .where((a) => a.stageId != null && a.stageId == s.stageId)
                        .toList(),
                  )),
              // 整单延时记录汇总（跨轮，标第几轮），默认只展示最近几条
              if (history.isNotEmpty) _ExtendRecordSummary(records: history),
            ],
          ),
        );
      },
    );
  }
}

/// 单轮时间线条目
class _StageTimelineItem extends ConsumerStatefulWidget {
  final DemandStage stage;
  final int demandId;
  final bool isBuyer;
  /// 本轮延时记录（申请延时与自主延时同表保留，按发生时间倒序）
  final List<DemandExtendApply> extendApplies;

  const _StageTimelineItem({
    required this.stage,
    required this.demandId,
    required this.isBuyer,
    this.extendApplies = const <DemandExtendApply>[],
  });

  @override
  ConsumerState<_StageTimelineItem> createState() => _StageTimelineItemState();
}

class _StageTimelineItemState extends ConsumerState<_StageTimelineItem> {
  bool _acting = false;

  /// 本轮延时记录是否展开全部（默认只展示最近 _extendPreviewCount 条）
  bool _extendExpanded = false;

  /// AI 审核在后台跑，轮次处于 ai_reviewing 时定时重拉，跑完自动展示结果
  Timer? _aiPollTimer;

  @override
  void initState() {
    super.initState();
    _syncAiPolling();
  }

  @override
  void didUpdateWidget(covariant _StageTimelineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAiPolling();
  }

  @override
  void dispose() {
    _aiPollTimer?.cancel();
    super.dispose();
  }

  void _syncAiPolling() {
    final reviewing = widget.stage.isAiReviewing;
    if (reviewing && _aiPollTimer == null) {
      _aiPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        ref.invalidate(demandStagesProvider(widget.demandId));
        ref.invalidate(demandDetailProvider(widget.demandId));
      });
    } else if (!reviewing && _aiPollTimer != null) {
      _aiPollTimer?.cancel();
      _aiPollTimer = null;
    }
  }

  Color get _statusColor {
    switch (widget.stage.status) {
      case 'approved': return Colors.green;
      case 'ai_reviewing': return Colors.purple;
      case 'submitted': return Colors.blue;
      case 'rejected': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData get _statusIcon {
    switch (widget.stage.status) {
      case 'approved': return Icons.check_circle;
      case 'ai_reviewing': return Icons.pending_actions;
      case 'submitted': return Icons.pending;
      case 'rejected': return Icons.cancel;
      default: return Icons.radio_button_unchecked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stage;
    final amountYuan = (s.amount ?? 0) / 100.0;
    // 已生效延时累计（申请通过 + 自主延时）：时限本身不变，这里直接标明已顺延多少
    final extendedHours = widget.extendApplies
        .where((a) => a.status == 'approved')
        .fold<int>(0, (sum, a) => sum + (a.days ?? 0) * 24 + (a.hours ?? 0));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧时间轴
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(_statusIcon, color: _statusColor, size: 22),
                if (s.stageOrder != (widget.stage.demandId != null ? 999 : 0))
                  Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 内容区
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _statusColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('第${s.stageOrder}轮',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 8),
                      Text('到第${s.episodeTo}集',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      const Spacer(),
                      // 轮次金额与下方「已放款」同一位（两位），同一面板内不能一个 ¥150 一个 ¥150.00
                      Text('¥${amountYuan.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600, color: _statusColor)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: _statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(s.statusLabel,
                            style: TextStyle(fontSize: 11, color: _statusColor)),
                      ),
                      if (s.releaseFlag == 1) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('已放款¥${amountYuan.toStringAsFixed(2)}（已入创作者待结算）',
                              style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                        ),
                      ],
                    ],
                  ),
                  // 本轮时限（各轮均展示，含后续未激活轮）；绝对截止/超时仅已激活轮
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 13, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '时限 ${s.durationText}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                      if (extendedHours > 0) ...[
                        const SizedBox(width: 10),
                        Text('已延时 ${formatDurationHours(extendedHours)}',
                            style:
                                TextStyle(fontSize: 12, color: Colors.green.shade700)),
                      ],
                      if (s.startedAt != null) ...[
                        const SizedBox(width: 10),
                        if (s.absoluteDueText != null)
                          Flexible(
                            child: Text(
                              '截止 ${s.absoluteDueText}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        if (s.isOverdueNow && s.status != 'approved')
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('⚠ 已超时',
                                style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                          ),
                      ],
                    ],
                  ),
                  // 交付作品
                  if (s.workId != null) ...[
                    const SizedBox(height: 6),
                    Text('交付作品：${s.workTitle ?? '作品${s.workId}'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    // 验收前得能读到正文，否则只能凭一句交付说明拍板（仅发布者可取，后端鉴权）。
                    // 待审核态的入口移到下方与「确认验收」同一行，这里只给非审核态（如已通过）保留。
                    if (widget.isBuyer && s.stageId != null && s.status != 'submitted') ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _acting ? null : _viewDeliveredWork,
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('查看交付内容',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ],
                  // 交付说明
                  if (s.deliverableDesc != null && s.deliverableDesc!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('交付说明：${s.deliverableDesc}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                  // 驳回原因
                  if (s.rejectReason != null && s.rejectReason!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('驳回原因：${s.rejectReason}',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
                  ],
                  // AI 审核结论（分数与去向）
                  if (s.aiVerdictText != null) ...[
                    const SizedBox(height: 4),
                    Text(s.aiVerdictText!,
                        style: TextStyle(
                            fontSize: 12,
                            color: (s.aiScore != null && s.aiScore! >= 60)
                                ? Colors.green.shade700
                                : Colors.purple)),
                  ],
                  // 审核暂停提示（AI 审核与人工验收均暂停计时）
                  if (s.isPausedForReview) ...[
                    const SizedBox(height: 4),
                    Text(
                      s.isAiReviewing
                          ? 'AI审核中，计时已暂停（AI审核耗时不计入本轮时限），结果稍后自动更新'
                          : '验收中，计时已暂停（审核耗时不计入本轮时限）',
                      style: TextStyle(
                          fontSize: 12,
                          color: s.isAiReviewing
                              ? Colors.purple
                              : Colors.blue.shade600,
                          height: 1.4),
                    ),
                  ],
                  // 延时记录：每条一行长期保留，超出预览条数折叠；历史未拉到前回退轮次行快照
                  if (widget.extendApplies.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('延时记录（${widget.extendApplies.length}条）',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700)),
                          const SizedBox(height: 2),
                          ..._visibleExtends.map((a) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  _extendRecordLine(a),
                                  style: TextStyle(
                                      fontSize: 12, color: _extendRecordColor(a.status), height: 1.4),
                                ),
                              )),
                          if (widget.extendApplies.length > _extendPreviewCount)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _extendExpanded = !_extendExpanded),
                              child: Text(
                                _extendExpanded
                                    ? '收起'
                                    : '展开全部（${widget.extendApplies.length}条）',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.primary),
                              ),
                            ),
                        ],
                      ),
                    )
                  else if (s.hasPendingExtend)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '申请延时 ${s.extendAskText}${(s.extendReason != null && s.extendReason!.isNotEmpty) ? '：${s.extendReason}' : ''}（待发布者处理）',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                    )
                  else if (s.extendStatus == 'approved')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('延时申请已同意，截止时间已顺延',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                    )
                  else if (s.extendStatus == 'rejected')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('延时申请已拒绝',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ),
                  // 操作区
                  ..._buildActions(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 本轮记录区默认展示条数，超出部分折叠为「展开全部」
  static const int _extendPreviewCount = 3;

  /// 当前展示的本轮延时记录（接口按发生时间倒序返回，折叠态只取最近几条）
  List<DemandExtendApply> get _visibleExtends => _extendExpanded
      ? widget.extendApplies
      : widget.extendApplies.take(_extendPreviewCount).toList();

  /// 是否为当前活动轮：已激活且未通过。
  bool get _isActiveRound {
    final s = widget.stage;
    return s.startedAt != null && s.status != 'approved';
  }

  /// 创作者可交付：活动轮且处于待交付/已驳回。
  bool get _canDeliver => !widget.isBuyer && _isActiveRound &&
      (widget.stage.status == 'pending' || widget.stage.status == 'rejected');

  /// 创作者可申请延时：可交付状态且无待处理申请。
  bool get _canRequestExtend => _canDeliver && !widget.stage.hasPendingExtend;

  /// 买方可审核：待审核。
  bool get _canReview => widget.isBuyer && widget.stage.status == 'submitted';

  /// 买方可处理延时申请：存在待处理申请。
  bool get _canDecideExtend => widget.isBuyer && widget.stage.hasPendingExtend;

  /// 买方可自主延时：活动轮且处于待交付/已驳回；
  /// 本轮已有待处理申请时不可再自延（否则与审核叠加造成双重顺延）。
  bool get _canSelfExtend => widget.isBuyer && _isActiveRound &&
      (widget.stage.status == 'pending' || widget.stage.status == 'rejected') &&
      !widget.stage.hasPendingExtend;

  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];
    // 买方：审核 + 处理延时申请
    if (_canReview) {
      actions.add(const SizedBox(height: 10));
      // 查看交付内容与验收操作同一行：验收前先把正文读一遍，再点「确认验收」选通过/驳回
      actions.add(Row(
        children: [
          if (widget.stage.stageId != null)
            TextButton.icon(
              onPressed: _acting ? null : _viewDeliveredWork,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('查看交付内容', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _acting ? null : () => _confirmReview(context),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('确认验收'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          ),
        ],
      ));
    }
    // 发布者：延时申请审核（左）+ 延长时间（右）同一行；无待处理申请时审核按钮置灰
    // 有待处理申请时「延长时间」置灰，避免自延 + 审核同意造成两次顺延
    if (widget.isBuyer && (_canSelfExtend || _canDecideExtend)) {
      actions.add(const SizedBox(height: 8));
      actions.add(Row(
        children: [
          Expanded(
            child: widget.stage.hasPendingExtend
                ? OutlinedButton(
                    onPressed: _acting ? null : () => _reviewExtendDialog(context),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade700),
                    child: const Text('延时审核'),
                  )
                : OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
                    child: const Text('无延时申请'),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: (_canSelfExtend && !_acting) ? () => _selfExtend(context) : null,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('延长时间'),
            ),
          ),
        ],
      ));
      if (widget.stage.hasPendingExtend) {
        actions.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('请先处理创作者的延时申请，处理前不可再自主延时（避免重复顺延）。',
              style: TextStyle(
                  fontSize: 11, color: Colors.orange.shade800, height: 1.4)),
        ));
      }
    }
    // 创作者：提交交付物 + 申请延长时间 同一行
    if (_canDeliver) {
      actions.add(const SizedBox(height: 10));
      actions.add(Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _acting ? null : () => _deliver(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('提交交付物'),
            ),
          ),
          if (_canRequestExtend) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _acting ? null : () => _requestExtend(context),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('申请延时'),
              ),
            ),
          ],
        ],
      ));
    }
    return actions;
  }

  /// 发布者审核本轮延时申请：展示申请信息后当场接受/拒绝（按 stageId 定位，任务×轮次相互独立）。
  Future<void> _reviewExtendDialog(BuildContext context) async {
    final s = widget.stage;
    final applied = s.extendAppliedAt;
    final appliedText = applied == null
        ? null
        : '${applied.month}月${applied.day}日 '
            '${applied.hour.toString().padLeft(2, '0')}:${applied.minute.toString().padLeft(2, '0')}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('第${s.stageOrder}轮 延时审核'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kvRow('申请延时', s.extendAskText),
              if (s.extendReason != null && s.extendReason!.isNotEmpty)
                _kvRow('申请原因', s.extendReason!),
              if (appliedText != null) _kvRow('申请时间', appliedText),
              const SizedBox(height: 4),
              Text('接受后将按申请时长顺延本轮截止时间。',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600, height: 1.4)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('拒绝', style: TextStyle(color: Colors.grey.shade700))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('接受',
                  style: TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == null) return;
    await _decideExtend(context, ok);
  }

  /// 弹窗内 label-value 信息行。
  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 64,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4))),
        ],
      ),
    );
  }

  /// 提取可读错误文案：业务异常取后端 message，其余回退默认。
  String _errText(Object e) =>
      e is ApiException && e.message.isNotEmpty ? e.message : '请稍后重试';

  /// 查看本轮交付正文（仅发布者）：跳全屏页，后端只下发本轮 episodeTo 内的集。
  void _viewDeliveredWork() {
    final s = widget.stage;
    final stageId = s.stageId;
    if (stageId == null) return;
    context.push(RoutePath.demandDeliverableWorkUrl(
        widget.demandId, stageId, s.stageOrder ?? 0));
  }

  /// 提交本轮交付：跳转全屏提交页（选作品+交付说明），提交后先进入 AI 审核。
  Future<void> _deliver(BuildContext context) async {
    final ok = await context.push<bool>(RoutePath.demandStageDeliverUrl(
        widget.demandId, widget.stage.stageId!, widget.stage.stageOrder ?? 0));
    if (ok == true) {
      ref.invalidate(demandStagesProvider(widget.demandId));
      ref.invalidate(demandDetailProvider(widget.demandId));
      if (mounted) showAppToast(context, '已提交，AI审核中，结果稍后自动更新');
    }
  }

  /// 创作者发起延时申请（按小时填写）。
  Future<void> _requestExtend(BuildContext context) async {
    final input = await _promptExtend(context,
        title: '申请延时', withReason: true);
    if (input == null) return;
    if (input.hours <= 0) {
      showAppToast(context, '延时小时数必须大于0');
      return;
    }
    setState(() => _acting = true);
    try {
      await ref.read(demandRepositoryProvider).requestExtend(
            widget.demandId,
            widget.stage.stageId!,
            days: 0,
            hours: input.hours,
            reason: input.reason.isEmpty ? null : input.reason,
          );
      ref.invalidate(demandStagesProvider(widget.demandId));
      ref.invalidate(demandExtendHistoryProvider(widget.demandId));
      if (mounted) showAppToast(context, '延时申请已提交，等待发布者处理');
    } catch (e) {
      if (mounted) showAppToast(context, '申请失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// 发布者延长时间（不经申请直接顺延本轮截止，并落一条自主延时记录）。
  Future<void> _selfExtend(BuildContext context) async {
    final input =
        await _promptExtend(context, title: '延长时间', withReason: false);
    if (input == null) return;
    if (input.hours <= 0) {
      showAppToast(context, '延时小时数必须大于0');
      return;
    }
    setState(() => _acting = true);
    try {
      await ref.read(demandRepositoryProvider).selfExtend(
            widget.demandId,
            widget.stage.stageId!,
            days: 0,
            hours: input.hours,
          );
      ref.invalidate(demandStagesProvider(widget.demandId));
      ref.invalidate(demandDetailProvider(widget.demandId));
      // 自主延时已落一条延时记录，刷新记录列表
      ref.invalidate(demandExtendHistoryProvider(widget.demandId));
      if (mounted) showAppToast(context, '已延长本轮截止时间');
    } catch (e) {
      if (mounted) showAppToast(context, '延时失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// 发布者处理延时申请。
  Future<void> _decideExtend(BuildContext context, bool approved) async {
    setState(() => _acting = true);
    try {
      await ref.read(demandRepositoryProvider).decideExtend(
            widget.demandId,
            widget.stage.stageId!,
            approved: approved,
          );
      ref.invalidate(demandStagesProvider(widget.demandId));
      ref.invalidate(demandExtendHistoryProvider(widget.demandId));
      if (mounted) showAppToast(context, approved ? '已同意延时' : '已拒绝延时');
    } catch (e) {
      if (mounted) showAppToast(context, '操作失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// 延时时长输入弹窗（统一按小时填写，可选原因）。
  Future<_ExtendInput?> _promptExtend(BuildContext context,
      {required String title, required bool withReason}) async {
    final hoursCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: hoursCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '延长小时数',
                    suffixText: '小时',
                    isDense: true),
              ),
              if (withReason) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: '延时原因（可选）', isDense: true),
                ),
              ],
              const SizedBox(height: 4),
              Text('按小时填写，展示时自动折算为天。',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: Colors.grey.shade700))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return null;
    return _ExtendInput(
      hours: int.tryParse(hoursCtrl.text.trim()) ?? 0,
      reason: reasonCtrl.text.trim(),
    );
  }

  /// 确认验收：把通过/驳回合并成一个入口，点击后在弹窗里二选一，避免误触直接放款。
  Future<void> _confirmReview(BuildContext context) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('第${widget.stage.stageOrder}轮 · 确认验收'),
        content: const Text(
          '建议先「查看交付内容」读一遍本轮正文再决定。\n'
          '通过：按本轮金额放款给创作者；驳回：退回创作者修改后重新提交。',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('驳回',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('通过',
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (!context.mounted) return;
    await _review(context, choice);
  }

  Future<void> _review(BuildContext context, bool approved) async {
    String? reason;
    if (!approved) {
      final ctrl = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('驳回交付物'),
          content: SizedBox(
            width: 300,
            child: TextField(
              controller: ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: '请输入驳回原因，便于创作者修改后重新提交',
                  isDense: true),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('取消', style: TextStyle(color: Colors.grey.shade700))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认驳回',
                    style:
                        TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
          ],
        ),
      );
      if (confirmed != true) return;
      reason = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
    }

    setState(() => _acting = true);
    try {
      await ref.read(demandRepositoryProvider).reviewStage(
            widget.demandId,
            widget.stage.stageId!,
            approved: approved,
            rejectReason: reason,
          );
      ref.invalidate(demandStagesProvider(widget.demandId));
      if (mounted) showAppToast(context, approved ? '已审核通过' : '已驳回');
    } catch (e) {
      if (mounted) showAppToast(context, '操作失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }
}

/// 延时输入弹窗的返回值（统一按小时、原因）。
class _ExtendInput {
  final int hours;
  final String reason;
  const _ExtendInput({required this.hours, required this.reason});
}

/// 一条延时记录的行文案：来源 · 时长（原因） · 结果 · 发生时间 [ · → 截止 新截止]。
/// 单轮卡片与整单汇总共用，保证两种视图同格式；[withRound] 额外标轮次。
String _extendRecordLine(DemandExtendApply a, {bool withRound = false}) {
  final reason = (a.reason == null || a.reason!.isEmpty) ? '' : '：${a.reason}';
  final time = a.appliedText;
  final due = a.dueAfterText;
  final round = withRound ? '第${a.stageOrder ?? 0}轮 · ' : '';
  return '$round${a.sourceLabel} ${a.askText}$reason · ${a.statusLabel}'
      '${time.isEmpty ? '' : ' · $time'}'
      '${due.isEmpty ? '' : ' · → 截止$due'}';
}

/// 延时记录状态颜色：待处理橙色 / 已同意与自主生效绿色 / 已驳回灰色。
Color _extendRecordColor(String? status) {
  switch (status) {
    case 'pending': return Colors.orange.shade800;
    case 'approved': return Colors.green.shade700;
    case 'rejected': return Colors.grey.shade600;
    default: return Colors.grey.shade700;
  }
}

/// 整单延时记录汇总（跨轮次，每条标第几轮），默认只列最近几条。
class _ExtendRecordSummary extends StatefulWidget {
  final List<DemandExtendApply> records;

  const _ExtendRecordSummary({required this.records});

  static const int previewCount = 3;

  @override
  State<_ExtendRecordSummary> createState() => _ExtendRecordSummaryState();
}

class _ExtendRecordSummaryState extends State<_ExtendRecordSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.records.length;
    final more = total > _ExtendRecordSummary.previewCount;
    final shown = _expanded || !more
        ? widget.records
        : widget.records.take(_ExtendRecordSummary.previewCount).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text('全部延时记录（$total条）',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              const Spacer(),
              if (more)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? '收起' : '展开全部',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.primary)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          ...shown.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  _extendRecordLine(a, withRound: true),
                  style: TextStyle(
                      fontSize: 12, color: _extendRecordColor(a.status), height: 1.4),
                ),
              )),
        ],
      ),
    );
  }
}
