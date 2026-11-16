import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai_models.dart';
import '../data/ai_providers.dart';
import 'ai_option_field.dart';

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
    final selectedLabel = displayValue == null
        ? null
        : options
            .firstWhere((o) => o.value == displayValue,
                orElse: () => _ModelOption(value: '', label: ''))
            .label;
    return AiOptionField(
      label: '模型',
      placeholder: '请选择模型',
      selectedLabel: selectedLabel,
      enabled: enabled,
      onTap: () async {
        final pick = await showAiOptionPicker<String>(
          context,
          title: '选择模型',
          selected: displayValue,
          options: [
            for (final option in options) AiOption<String>(value: option.value, label: option.label),
          ],
        );
        if (pick != null) onChanged(pick.value);
      },
    );
  }
}

/// 扁平模型选项（value=模型名，label=渠道前缀展示文案）。
class _ModelOption {
  const _ModelOption({required this.value, required this.label});

  final String value;
  final String label;
}
