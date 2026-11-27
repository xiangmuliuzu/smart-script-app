import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../ai/widgets/ai_model_selector.dart';
import '../../ai/widgets/ai_skill_selector.dart';

/// 作品设定页（AI 创作第一步）。
///
/// 三段结构对齐原型：1 · 作品（书名 / 故事灵感）、2 · 题材（chips）、
/// 3 · 创作要求（你的要求 + 模型 + 可展开的「高级参数：导演 Skill」）。
///
/// 集数与单集时长不再由作者填写：后端 `BlueprintService.setup()` 缺省按 12 集 / 2 分钟兜底，
/// 分集大纲也不在资料阶段生成（每章写作时现生成）。
class BlueprintSetupForm extends StatefulWidget {
  const BlueprintSetupForm({
    super.key,
    required this.titleController,
    required this.ideaController,
    required this.requirementController,
    required this.selectedGenres,
    required this.onGenresChanged,
    required this.selectedModel,
    required this.onModelChanged,
    required this.selectedSkillId,
    required this.onSkillChanged,
    this.enabled = true,
  });

  final TextEditingController titleController;
  final TextEditingController ideaController;
  final TextEditingController requirementController;
  final Set<String> selectedGenres;
  final ValueChanged<Set<String>> onGenresChanged;
  final String? selectedModel;
  final ValueChanged<String?> onModelChanged;
  final int? selectedSkillId;
  final ValueChanged<int?> onSkillChanged;
  final bool enabled;

  /// 题材选项（与 PC v3 `AiCreate.vue` 的 genres 一致，由后端按自由文本接收）。
  static const List<String> genres = <String>[
    '都市悬疑',
    '都市情感',
    '玄幻冒险',
    '古装权谋',
    '科幻未来',
    '青春校园',
  ];

  /// 灵感最少字数（与 PC v3 校验一致）。
  static const int ideaMinLength = 10;
  static const int ideaMaxLength = 2000;
  static const int requirementMaxLength = 1000;

  @override
  State<BlueprintSetupForm> createState() => _BlueprintSetupFormState();
}

class _BlueprintSetupFormState extends State<BlueprintSetupForm> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('1 · 作品'),
        _SetupCard(
          child: Column(
            children: [
              _SetupField(
                label: '书名',
                child: TextField(
                  controller: widget.titleController,
                  enabled: widget.enabled,
                  maxLength: 100,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: '例如：深夜频率',
                    counterText: '',
                  ),
                ),
              ),
              _SetupField(
                label: '故事灵感',
                last: true,
                child: TextField(
                  controller: widget.ideaController,
                  enabled: widget.enabled,
                  maxLines: 4,
                  minLines: 3,
                  maxLength: BlueprintSetupForm.ideaMaxLength,
                  decoration: const InputDecoration(
                    hintText: '一句话讲清人物、冲突与悬念，例如：一位深夜电台主播在听众留言里听到了十年前的自己。',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
        ),
        const _SectionLabel('2 · 题材', top: 18),
        _SetupCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final genre in BlueprintSetupForm.genres)
                _GenreChip(
                  label: genre,
                  selected: widget.selectedGenres.contains(genre),
                  enabled: widget.enabled,
                  onTap: () {
                    final next = Set<String>.of(widget.selectedGenres);
                    if (!next.remove(genre)) next.add(genre);
                    widget.onGenresChanged(next);
                  },
                ),
            ],
          ),
        ),
        const _SectionLabel('3 · 创作要求', top: 18),
        _SetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SetupField(
                label: '你的要求',
                child: TextField(
                  controller: widget.requirementController,
                  enabled: widget.enabled,
                  maxLines: 3,
                  minLines: 2,
                  maxLength: BlueprintSetupForm.requirementMaxLength,
                  decoration: const InputDecoration(
                    hintText: '第一集就出现异常线索。人物对白自然，结尾保留一个能推动下一集的悬念。',
                    counterText: '',
                  ),
                ),
              ),
              AiModelSelector(
                selectedModel: widget.selectedModel,
                onChanged: widget.onModelChanged,
                enabled: widget.enabled,
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.rSmall),
                onTap: widget.enabled
                    ? () => setState(() => _advancedOpen = !_advancedOpen)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        _advancedOpen ? '收起高级参数' : '高级参数：导演 Skill',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.text3),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _advancedOpen ? Icons.expand_less : Icons.chevron_right,
                        size: 16,
                        color: AppColors.text3,
                      ),
                    ],
                  ),
                ),
              ),
              if (_advancedOpen)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AiSkillSelector(
                    selectedSkillId: widget.selectedSkillId,
                    onChanged: widget.onSkillChanged,
                    enabled: widget.enabled,
                    skillTypeFilter: 'write',
                  ),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 14, 2, 0),
          child: Text(
            '资料只生成作品级内容：故事核心、世界与规则、主要人物、关键物品。分集大纲在写每一章时现生成。',
            style: TextStyle(fontSize: 12, height: 1.7, color: AppColors.text3),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.top = 0});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2, top, 2, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 0.4,
          color: AppColors.text3,
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}

class _SetupField extends StatelessWidget {
  const _SetupField({required this.label, required this.child, this.last = false});

  final String label;
  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.text2),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
