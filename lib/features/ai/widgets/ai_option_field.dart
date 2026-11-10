import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 选项（[value] 为 null 表示「默认 / 不限」这类空选择）。
class AiOption<T> {
  const AiOption({required this.value, required this.label, this.subtitle});

  final T? value;
  final String label;
  final String? subtitle;
}

/// 选择结果：区分「点了某个选项」与「直接关掉弹层」。
class AiPick<T> {
  const AiPick(this.value);
  final T? value;
}

/// 统一的「字段 + 箭头」样式，点击弹出底部选择面板。
///
/// 替换原生 [DropdownButton]：原生菜单在 Android 上是系统灰白浮层，
/// 与 App 的浅色卡片风格不统一，长选项还会被裁切。
class AiOptionField extends StatelessWidget {
  const AiOptionField({
    super.key,
    required this.label,
    required this.placeholder,
    required this.onTap,
    this.selectedLabel,
    this.enabled = true,
  });

  final String label;
  final String placeholder;
  final String? selectedLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = selectedLabel != null && selectedLabel!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
        const SizedBox(height: 8),
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasValue ? selectedLabel! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: hasValue ? AppColors.text1 : AppColors.text3,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: enabled ? AppColors.text3 : AppColors.placeholder),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 弹出底部选项面板；返回 null 表示用户没有选择（点了遮罩或下滑关闭）。
Future<AiPick<T>?> showAiOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<AiOption<T>> options,
  required T? selected,
}) {
  return showModalBottomSheet<AiPick<T>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.7;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final option in options)
                      ListTile(
                        title: Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: option.value == selected
                                ? AppColors.primary
                                : AppColors.text1,
                            fontWeight: option.value == selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        subtitle: option.subtitle == null
                            ? null
                            : Text(option.subtitle!,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.text3)),
                        trailing: option.value == selected
                            ? const Icon(Icons.check_rounded,
                                size: 20, color: AppColors.primary)
                            : null,
                        onTap: () =>
                            Navigator.of(sheetContext).pop(AiPick<T>(option.value)),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
