import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import 'country_code_picker.dart';
import 'underlined_input.dart';

/// 手机号输入行：默认 +86 区号、仅数字、11 位。
class PhoneInput extends StatelessWidget {
  const PhoneInput({
    super.key,
    required this.controller,
    this.errorText,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? errorText;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return UnderlinedInput(
      controller: controller,
      hintText: '请输入手机号',
      leading: const CountryCodePicker(),
      errorText: errorText,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      maxLength: AppConfig.phoneLength,
      // 只允许数字：粘贴带空格 / 横线的号码也会被过滤
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
    );
  }
}
