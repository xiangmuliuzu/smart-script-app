import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 圆角白色分组卡片：去掉全屏通栏分割线后，页面内容以卡片分组呈现。
class UserFormCard extends StatelessWidget {
  const UserFormCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.r)),
        boxShadow: AppColors.cardShadow,
      ),
      // 上下统一 4 的呼吸感，行与行之间由 UserFormField 自带的内边距撑开。
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    );
  }
}

/// 表单行：左侧固定宽度标签 + 右侧左对齐内容。
///
/// 输入框与只读值共用同一套内边距与标签宽度，保证输入内容与只读信息的起点对齐。
class UserFormField extends StatelessWidget {
  const UserFormField({
    super.key,
    required this.label,
    required this.child,
    this.showDivider = true,
  });

  final String label;
  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: AppColors.divider, width: 0.5)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Padding(
              // 与右侧单行文本的首行基线对齐。
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: AppColors.text2),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 无边框透明输入框：去掉外描边与默认填充，文字下沉到卡片内。
class UserPlainTextField extends StatelessWidget {
  const UserPlainTextField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.maxLength,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final int maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      minLines: 1,
      maxLength: maxLength,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.text1,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        // 主题里给输入框统一加了填充与描边，这里显式清空。
        fillColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.placeholder,
        ),
      ),
    );
  }
}

/// 表单主操作按钮：深主色实心胶囊，带主色投影。
class UserPrimaryButton extends StatelessWidget {
  const UserPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.busy,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: BorderRadius.circular(24),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x331E4078),
                    offset: Offset(0, 6),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
