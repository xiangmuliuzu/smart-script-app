import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/ai_models.dart';
import '../data/ai_providers.dart';

/// 「导演(skill)选择」下拉（App 端 AI 创作页共用）。
///
/// 数据源 GET /api/v1/content/ai/skills（管理员端上传配置）；
/// 未配置时显示「默认导演」。选中值通过 [onChanged] 回调给页面。
class AiSkillSelector extends ConsumerWidget {
  const AiSkillSelector({
    super.key,
    required this.selectedSkillId,
    required this.onChanged,
    this.enabled = true,
  });

  final int? selectedSkillId;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(aiSkillsProvider).valueOrNull ?? const <AiSkill>[];
    final current = skills.firstWhere(
      (skill) => skill.id == selectedSkillId,
      orElse: () => AiSkill(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('导演(skill)',
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
            child: DropdownButton<int?>(
              value: selectedSkillId,
              isExpanded: true,
              hint: const Text('默认导演',
                  style: TextStyle(fontSize: 14, color: AppColors.text3)),
              items: [
                DropdownMenuItem<int?>(
                    value: null,
                    child: Text('默认导演',
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.text2))),
                for (final skill in skills)
                  DropdownMenuItem<int?>(
                      value: skill.id,
                      child: Text(skill.skillName,
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
        if (current.id != 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('当前导演：${current.skillName}',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.text3)),
          ),
      ],
    );
  }
}
