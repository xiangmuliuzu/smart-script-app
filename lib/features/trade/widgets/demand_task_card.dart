import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/demand_genre.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/trade_models.dart';

/// 任务广场门户卡片。
///
/// 视觉规范：
/// - 左侧竖色条按题材着色（[DemandGenre.colorOf]），一眼分类型；
/// - 右上状态 chip：待接单绿 / 进行中蓝 / 已完成 primary / 逾期红 / 已关闭灰；
/// - 底部一行三段布局：预算大字 + 剩余时限/截止徽章 + 接单人·发布者；
/// - 需求预览与 tags 均"缺省即省略"，卡片高度自适应避免大片留白。
class DemandTaskCard extends StatelessWidget {
  const DemandTaskCard({super.key, required this.task, this.isMine = false, this.onTap});

  final DemandTask task;

  /// 当前登录用户是否为该任务的发布方（广场可接单卡片中若为自己发布的，用于隐藏接单入口等）。
  final bool isMine;

  /// 点击行为覆盖：列表页传入后在 navigate pop 返回时刷新分页/统计；
  /// 为 null 时默认直接推入任务详情。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = DemandGenre.colorOf(task.genreId);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.r),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap ??
                (task.demandId == null
                    ? null
                    : () => context.push(RoutePath.demandDetailUrl(task.demandId!))),
            child: Ink(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: accent.withOpacity(0.85), width: 3)),
              ),
              child: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final tags = _parseTags(task.tags);
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title ?? '未命名任务',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isMine)
                Container(
                  margin: const EdgeInsets.only(right: 6, top: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 0.6),
                  ),
                  child: const Text(
                    '我发布的',
                    style: TextStyle(fontSize: 10, color: AppColors.text1, fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(width: 8),
              _StatusChip(task: task),
            ],
          ),
          if ((task.requirement ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              task.requirement!.trim(),
              style: const TextStyle(fontSize: 12, color: AppColors.text3, height: 1.4),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (tags.isNotEmpty || task.genreId != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (task.genreId != null)
                  _TagPill(text: DemandGenre.labelOf(task.genreId), color: DemandGenre.colorOf(task.genreId)),
                for (final t in tags) _TagPill(text: t, color: AppColors.text2),
              ],
            ),
          ],
          const SizedBox(height: 11),
          Container(height: 0.6, color: AppColors.divider),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _BudgetBlock(budgetFen: task.budget),
              const SizedBox(width: 10),
              _DeadlineBadge(task: task),
              const Spacer(),
              _PublisherBlock(
                task: task,
                publisherName: task.clientName,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static List<String> _parseTags(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    return raw
        .split(RegExp(r'[,，;；]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.task});
  final DemandTask task;

  static Color _color(DemandTask t) {
    if (t.isOverdue == 1) return AppColors.danger;
    switch (t.status) {
      case DemandStatus.open:
        return AppColors.success;
      case DemandStatus.inProgress:
        return AppColors.text2;
      case DemandStatus.completed:
      case DemandStatus.selected:
        return AppColors.primary;
      case DemandStatus.failed:
        return AppColors.danger;
      default:
        return AppColors.text3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(task);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.35), width: 0.8),
      ),
      child: Text(
        task.statusLabel,
        style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _BudgetBlock extends StatelessWidget {
  const _BudgetBlock({required this.budgetFen});
  final int? budgetFen;

  @override
  Widget build(BuildContext context) {
    final fen = budgetFen ?? 0;
    // 金额一律两位小数：与详情页 budgetYuan、轮次面板、PC 端 fenText 同一口径，
    // 不能因为“整元就省略小数”让同一列里出现 ¥600 与 ¥600.50 两种位数
    final yuan = (fen / 100).toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: '¥ ',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.text1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: yuan,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppColors.text1,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '总预算',
          style: TextStyle(fontSize: 10, color: AppColors.text3),
        ),
      ],
    );
  }
}

class _DeadlineBadge extends StatefulWidget {
  const _DeadlineBadge({required this.task});
  final DemandTask task;

  @override
  State<_DeadlineBadge> createState() => _DeadlineBadgeState();
}

class _DeadlineBadgeState extends State<_DeadlineBadge> {
  Timer? _timer;

  DemandTask get task => widget.task;

  /// 仅"进行中且未逾期且有应完成时间"时存在实时倒计时，需周期刷新；
  /// 其余（待接单按天粒度、终态）不启动定时器，避免整屏卡片无谓重建。
  bool get _needsTick =>
      task.status == DemandStatus.inProgress && task.dueAt != null && task.isOverdue != 1;

  @override
  void initState() {
    super.initState();
    if (_needsTick) {
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

  _DeadlineInfo get _info {
    // 逾期优先
    if (task.isOverdue == 1) return const _DeadlineInfo('已逾期', _DeadlineTone.overdue);
    final status = task.status;
    if (status == DemandStatus.closed) return const _DeadlineInfo('已关闭', _DeadlineTone.closed);
    if (status == DemandStatus.failed) return const _DeadlineInfo('已失败', _DeadlineTone.overdue);
    if (status == DemandStatus.completed) return const _DeadlineInfo('已完成', _DeadlineTone.selected);
    // 进行中：基于应完成时间 dueAt 倒计时
    if (status == DemandStatus.inProgress) {
      final due = task.dueAt;
      if (due == null) return const _DeadlineInfo('进行中', _DeadlineTone.neutral);
      final remain = due.difference(DateTime.now());
      if (remain.isNegative) return const _DeadlineInfo('已逾期', _DeadlineTone.overdue);
      final h = remain.inHours;
      if (h < 24) return _DeadlineInfo('剩 $h 小时', _DeadlineTone.urgent);
      return _DeadlineInfo('剩 ${h ~/ 24} 天', _DeadlineTone.neutral);
    }
    // 待接单（open）：基于发布截止日 deadline
    final dt = task.deadline;
    if (dt == null) return const _DeadlineInfo('长期', _DeadlineTone.neutral);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = target.difference(today).inDays;
    if (diff < 0) return const _DeadlineInfo('已过期', _DeadlineTone.overdue);
    if (diff == 0) return const _DeadlineInfo('今天到期', _DeadlineTone.urgent);
    if (diff == 1) return const _DeadlineInfo('明天到期', _DeadlineTone.urgent);
    if (diff <= 3) return _DeadlineInfo('剩 $diff 天', _DeadlineTone.urgent);
    return _DeadlineInfo('${dt.month}月${dt.day}日截止', _DeadlineTone.neutral);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final (Color bg, Color fg) = switch (info.tone) {
      _DeadlineTone.overdue => (AppColors.danger.withOpacity(0.08), AppColors.danger),
      _DeadlineTone.urgent => (AppColors.warning.withOpacity(0.10), AppColors.warning),
      _DeadlineTone.closed => (AppColors.fill, AppColors.text3),
      _DeadlineTone.selected => (AppColors.primaryTint, AppColors.primary),
      _DeadlineTone.neutral => (AppColors.fill, AppColors.text2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(task.status == DemandStatus.inProgress ? Icons.timer_outlined : Icons.schedule,
              size: 11, color: fg),
          const SizedBox(width: 3),
          Text(info.label,
              style: TextStyle(fontSize: 10.5, color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PublisherBlock extends StatelessWidget {
  const _PublisherBlock({required this.task, required this.publisherName});
  final DemandTask task;
  final String? publisherName;

  @override
  Widget build(BuildContext context) {
    final name = (publisherName ?? '').trim();
    // 接单人状态文案
    final String statusText;
    if (task.isOverdue == 1) {
      statusText = '已逾期';
    } else {
      switch (task.status) {
        case DemandStatus.open: statusText = '待接单';
        case DemandStatus.inProgress: statusText = '已接单';
        case DemandStatus.completed: statusText = '已完成';
        default: statusText = DemandStatus.label(task.status);
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 9,
          backgroundColor: AppColors.primaryTint,
          child: Text(
            name.isEmpty ? '·' : name.substring(0, 1),
            style: const TextStyle(fontSize: 9.5, color: AppColors.text1, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              statusText,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 92),
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.text3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

enum _DeadlineTone { overdue, urgent, closed, selected, neutral }

class _DeadlineInfo {
  final String label;
  final _DeadlineTone tone;
  const _DeadlineInfo(this.label, this.tone);
}

/// 首屏骨架屏占位（卡片样式的静态灰块）：
/// 替代整屏转圈，让列表区在加载时就呈现最终布局形状，减少跳动。
class DemandCardSkeleton extends StatelessWidget {
  const DemandCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _bar(w: 150, h: 13),
              const Spacer(),
              _bar(w: 46, h: 16, radius: 4),
            ],
          ),
          const SizedBox(height: 10),
          _bar(w: 240, h: 9),
          const SizedBox(height: 9),
          Row(
            children: [
              _bar(w: 40, h: 14, radius: 3),
              const SizedBox(width: 6),
              _bar(w: 52, h: 14, radius: 3),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              _bar(w: 70, h: 15),
              const SizedBox(width: 10),
              _bar(w: 52, h: 11),
              const Spacer(),
              _bar(w: 44, h: 11),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar({required double w, required double h, double radius = 5}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.placeholder.withOpacity(0.32),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
