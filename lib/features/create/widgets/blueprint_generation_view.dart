import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/blueprint_models.dart';

/// 「生成中」卡片：标题 + 5 项资料进度（故事核心 / 世界与规则 / 主要人物 / 关键物品 / 人物关系）。
///
/// 进度完全由后端 SSE `event:stage` 驱动（[BlueprintStageProgress]），本组件只负责呈现：
/// 进行中显示旋转光环，完成显示 ✓，失败显示感叹号与重试入口。
class BlueprintGenerationView extends StatelessWidget {
  const BlueprintGenerationView({
    super.key,
    required this.title,
    required this.progress,
    this.failed = false,
    this.error = '',
    this.onRetry,
  });

  /// 作品书名（用于「正在生成《xxx》的作品资料」）。
  final String title;
  final BlueprintStageProgress progress;
  final bool failed;
  final String error;
  final VoidCallback? onRetry;

  bool get _done => progress.allDone && !failed;

  @override
  Widget build(BuildContext context) {
    final bookTitle = title.trim().isEmpty ? '作品' : '《$title》';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          _Orb(state: failed ? _OrbState.failed : (_done ? _OrbState.done : _OrbState.running)),
          const SizedBox(height: 16),
          Text(
            failed
                ? '生成中断'
                : _done
                    ? '$bookTitle的资料已生成'
                    : '正在生成$bookTitle的作品资料',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            failed
                ? (error.isEmpty ? '网络或服务异常，请重试' : error)
                : _done
                    ? '资料已生成，确认之后才会写入作品。'
                    : '按你的设定写故事、人物、物品与关系',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: failed ? AppColors.danger : AppColors.text3,
            ),
          ),
          const SizedBox(height: 22),
          for (var index = 0; index < BlueprintStageProgress.labels.length; index++)
            _StageRow(
              label: BlueprintStageProgress.labels[index],
              state: failed && index > 0 ? 'pending' : progress.stateOf(index),
            ),
          if (failed && onRetry != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新生成'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.state});

  final String label;

  /// done / run / pending。
  final String state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'run' => AppColors.text1,
      'done' => AppColors.text2,
      _ => AppColors.text3,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _StageDot(state: state),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 14, color: color)),
          const Spacer(),
          if (state == 'done')
            const Icon(Icons.check_rounded, size: 16, color: AppColors.text3)
          else if (state == 'run')
            const Text('整理中…',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
        ],
      ),
    );
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    if (state == 'done') {
      return Container(
        width: 15,
        height: 15,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 10, color: Colors.white),
      );
    }
    if (state == 'run') {
      return Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              spreadRadius: 4,
            ),
          ],
        ),
      );
    }
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.divider, width: 1.5),
      ),
    );
  }
}

enum _OrbState { running, done, failed }

/// 生成光环：进行中旋转细弧；完成 / 失败为实心圆 + 图标。
class _Orb extends StatefulWidget {
  const _Orb({required this.state});
  final _OrbState state;

  @override
  State<_Orb> createState() => _OrbWidgetState();
}

class _OrbWidgetState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.state == _OrbState.running) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _Orb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == _OrbState.running) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 54.0;
    if (widget.state != _OrbState.running) {
      final failed = widget.state == _OrbState.failed;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: failed ? AppColors.danger : AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          failed ? Icons.priority_high_rounded : Icons.check_rounded,
          color: Colors.white,
          size: 26,
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _OrbPainter(angle: _controller.value * math.pi * 2),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.angle});

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1.5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // 底环（很淡）与一段深色弧组成旋转光环。
    canvas.drawCircle(center, radius, paint..color = AppColors.primary.withOpacity(0.10));
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primary.withOpacity(0.6);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle,
      math.pi * 0.42,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.angle != angle;
}
