import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai_models.dart';
import '../data/ai_providers.dart';
import 'ai_option_field.dart';

/// 「导演(skill)选择」下拉（App 端 AI 创作页共用）。
///
/// 数据源 GET /api/v1/content/ai/skills（管理员端上传配置）；
/// 未选择时显示「请选择导演」占位（不传 skillId 由后端按默认处理）。选中值通过 [onChanged] 回调给页面。
class AiSkillSelector extends ConsumerWidget {
  const AiSkillSelector({
    super.key,
    required this.selectedSkillId,
    required this.onChanged,
    this.enabled = true,
    this.skillTypeFilter,
  });

  final int? selectedSkillId;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  /// 按用途过滤：'storyboard' 只列分镜类 skill，'write' 只列剧本/写作/润色类；
  /// null 表示不过滤（全部展示）。
  final String? skillTypeFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(aiSkillsProvider).valueOrNull ?? const <AiSkill>[];
    final skills = skillTypeFilter == null
        ? all
        : all
            .where((s) =>
                s.skillType == skillTypeFilter || s.skillType.isEmpty)
            .toList();
    final current = skills.firstWhere(
      (skill) => skill.id == selectedSkillId,
      orElse: () => AiSkill(),
    );
    final selectedLabel = selectedSkillId == null
        ? null
        : current.skillName.isEmpty
            ? null
            : current.skillName;
    return AiOptionField(
      label: '导演(skill)',
      placeholder: '请选择导演',
      selectedLabel: selectedLabel,
      enabled: enabled,
      onTap: () async {
        final pick = await showAiOptionPicker<int>(
          context,
          title: '选择导演 (skill)',
          selected: selectedSkillId,
          options: [
            for (final skill in skills)
              AiOption<int>(value: skill.id, label: skill.skillName),
          ],
        );
        if (pick != null) onChanged(pick.value);
      },
    );
  }
}
