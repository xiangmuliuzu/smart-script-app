import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/ai_models.dart';
import '../data/ai_providers.dart';

/// 「模型选择」下拉（App 端 AI 创作页共用）。
///
/// 数据源 GET /api/v1/content/ai/models（管理员端配置的启用渠道，无 apiKey）；
/// 未选择时显示「请选择模型」占位（不传模型名由后端按默认路由）。
/// 同一模型名可能出现在多个渠道，
/// 选项文案带渠道名前缀以便区分。选中值通过 [onChanged] 回调给页面。
class AiModelSelector extends ConsumerWidget {
  const AiModelSelector({
    super.key,
    required this.selectedModel,
    required this.onChanged,
    this.enabled = true,
  });

  final String? selectedModel;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels =
        ref.watch(aiChannelsProvider).valueOrNull ?? const <AiChannel>[];
    // 扁平模型选项：value 为模型名，label 带渠道前缀（渠道下同名模型可区分）。
    final options = <_ModelOption>[];
    for (final channel in channels) {
      for (final model in channel.models) {
        final defaultTag = model == channel.defaultModel ? '（默认）' : '';
        options.add(_ModelOption(
          value: model,
          label: '${channel.channelName} · $model$defaultTag',
        ));
      }
    }
    // 当前选中值若已被渠道停用/模型删除，回退为未选择占位。
    final selectedValid =
        selectedModel == null || options.any((o) => o.value == selectedModel);
    final displayValue = selectedValid ? selectedModel : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('模型',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(AppRadius.rSmall),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: displayValue,
              isExpanded: true,
              hint: const Text('请选择模型',
                  style: TextStyle(fontSize: 14, color: AppColors.text3)),
              items: [
                for (final option in options)
                  DropdownMenuItem<String?>(
                      value: option.value,
                      child: Text(option.label,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.text2))),
              ],
              onChanged: enabled ? onChanged : null,
              style: const TextStyle(fontSize: 14, color: AppColors.text2),
              icon: const Icon(Icons.arrow_drop_down,
                  color: AppColors.text3),
            ),
          ),
        ),
        if (selectedModel != null && selectedModel!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('当前模型：$selectedModel',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.text3)),
          ),
      ],
    );
  }
}

/// 扁平模型选项（value=模型名，label=渠道前缀展示文案）。
class _ModelOption {
  const _ModelOption({required this.value, required this.label});

  final String value;
  final String label;
}
