import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 用户协议勾选区域。
///
/// 交互：
///   * 圆圈勾选框，点击整行或圆圈都可切换；
///   * 《用户协议》《隐私政策》文字可点击，跳转对应页面；
///   * 未勾选就提交时由页面递增 [shakeSignal]，本组件播放抖动动画并高亮提示用户。
class AgreementCheckbox extends StatefulWidget {
  const AgreementCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.onUserAgreementTap,
    this.onPrivacyPolicyTap,
    this.shakeSignal = 0,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onUserAgreementTap;
  final VoidCallback? onPrivacyPolicyTap;

  /// 抖动触发信号：数值变化即播放一次抖动动画。
  final int shakeSignal;

  @override
  State<AgreementCheckbox> createState() => _AgreementCheckboxState();
}

class _AgreementCheckboxState extends State<AgreementCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  late final TapGestureRecognizer _userAgreementRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -7), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -7, end: 7), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 7, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 3), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 3, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    // 手势识别器必须手动释放，避免内存泄漏
    _userAgreementRecognizer = TapGestureRecognizer()
      ..onTap = () => widget.onUserAgreementTap?.call();
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => widget.onPrivacyPolicyTap?.call();
  }

  @override
  void didUpdateWidget(covariant AgreementCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shakeSignal != oldWidget.shakeSignal) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _userAgreementRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: _CheckCircle(checked: widget.value),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.text2,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(text: '我已阅读并同意'),
                      TextSpan(
                        text: '《用户协议》',
                        style: const TextStyle(color: AppColors.primary),
                        recognizer: _userAgreementRecognizer,
                      ),
                      const TextSpan(text: '和'),
                      TextSpan(
                        text: '《隐私政策》',
                        style: const TextStyle(color: AppColors.primary),
                        recognizer: _privacyRecognizer,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆形勾选框，勾选后填充主色并显示对勾。
class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: checked ? AppColors.primary : AppColors.text3,
          width: 1.4,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 12, color: Colors.white)
          : null,
    );
  }
}
