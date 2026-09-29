import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import 'underlined_input.dart';

/// 验证码输入行：左侧标签 + 输入框 + 「获取验证码」按钮（含倒计时）。
///
/// 交互约定：
///   * 倒计时期间按钮置灰不可重复点击；
///   * 请求失败（网络异常 / 频控 / 手机号非法）**不进入倒计时**，按钮立即恢复可点；
///   * 页面销毁时释放 Timer，绝不在销毁后 setState。
class VerifyCodeInput extends StatefulWidget {
  const VerifyCodeInput({
    super.key,
    required this.controller,
    required this.onRequestCode,
    this.errorText,
    this.focusNode,
    this.cooldownSeconds = AppConfig.smsCooldownSeconds,
    this.hintText = '请输入验证码',
    this.sendLabel = '获取验证码',
    this.textInputAction = TextInputAction.done,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;

  /// 请求验证码：返回 true 表示已成功发出（开始倒计时），false 表示失败。
  final Future<bool> Function() onRequestCode;

  final String? errorText;
  final FocusNode? focusNode;
  final int cooldownSeconds;
  final String hintText;
  final String sendLabel;
  final TextInputAction textInputAction;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<VerifyCodeInput> createState() => _VerifyCodeInputState();
}

class _VerifyCodeInputState extends State<VerifyCodeInput> {
  Timer? _timer;
  int _secondsLeft = 0;
  bool _sending = false;

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  Future<void> _handleRequest() async {
    if (_sending || _secondsLeft > 0 || !widget.enabled) {
      return;
    }
    setState(() => _sending = true);
    bool success = false;
    try {
      success = await widget.onRequestCode();
    } catch (_) {
      // 异常一律视为发送失败：按钮恢复可点，避免用户被卡在倒计时里
      success = false;
    }
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    if (success) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = widget.cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsLeft -= 1;
        if (_secondsLeft <= 0) {
          _secondsLeft = 0;
          timer.cancel();
          _timer = null;
        }
      });
    });
  }

  bool get _canSend => widget.enabled && !_sending && _secondsLeft == 0;

  String get _buttonLabel {
    if (_secondsLeft > 0) {
      return '${_secondsLeft}s';
    }
    return _sending ? '发送中' : widget.sendLabel;
  }

  @override
  Widget build(BuildContext context) {
    return UnderlinedInput(
      controller: widget.controller,
      hintText: widget.hintText,
      label: '验证码',
      errorText: widget.errorText,
      keyboardType: TextInputType.number,
      textInputAction: widget.textInputAction,
      maxLength: AppConfig.smsCodeMaxLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      focusNode: widget.focusNode,
      onSubmitted: widget.onSubmitted,
      trailing: SizedBox(
        width: 96,
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _canSend ? _handleRequest : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _buttonLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _canSend ? AppColors.primary : AppColors.text3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
