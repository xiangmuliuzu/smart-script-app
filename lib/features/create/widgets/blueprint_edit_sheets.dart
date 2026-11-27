import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/blueprint_models.dart';
import '../data/chapter_meta_models.dart';
import 'blueprint_text_edit_sheet.dart';
import 'blueprint_visuals.dart';

/// 作品资料的可编辑字段。
class BlueprintField {
  const BlueprintField({
    required this.label,
    required this.value,
    this.multiline = false,
    this.hintText,
    this.maxLength,
    this.helperText,
  });

  final String label;
  final String value;
  final bool multiline;
  final String? hintText;
  final int? maxLength;
  final String? helperText;
}

/// 多字段编辑弹层：底部弹出、键盘不遮挡，返回「字段标签 → 新值」。
///
/// 保存按钮总是可用（允许清空后保存），空值是否落库由调用方决定：
/// 台账字段空串表示清空、null 表示不改。
Future<Map<String, String>?> showBlueprintFieldsSheet(
  BuildContext context, {
  required String title,
  String subtitle = '保存后整段替换',
  required List<BlueprintField> fields,
  bool enabled = true,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _FieldsSheet(
      title: title,
      subtitle: subtitle,
      fields: fields,
      enabled: enabled,
    ),
  );
}

class _FieldsSheet extends StatefulWidget {
  const _FieldsSheet({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.enabled,
  });

  final String title;
  final String subtitle;
  final List<BlueprintField> fields;
  final bool enabled;

  @override
  State<_FieldsSheet> createState() => _FieldsSheetState();
}

class _FieldsSheetState extends State<_FieldsSheet> {
  late final List<TextEditingController> _controllers;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final field in widget.fields)
        TextEditingController(text: field.value),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(<String, String>{
      for (var index = 0; index < widget.fields.length; index++)
        widget.fields[index].label: _controllers[index].text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                height: 4,
                alignment: Alignment.center,
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(widget.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 3, 16, 8),
                child: Text(widget.subtitle,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.text3)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0;
                          index < widget.fields.length;
                          index++)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom: index == widget.fields.length - 1 ? 0 : 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.fields[index].label,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: AppColors.text2)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _controllers[index],
                                enabled: widget.enabled,
                                maxLines:
                                    widget.fields[index].multiline ? null : 1,
                                minLines:
                                    widget.fields[index].multiline ? 4 : 1,
                                maxLength: widget.fields[index].maxLength,
                                keyboardType: widget.fields[index].multiline
                                    ? TextInputType.multiline
                                    : TextInputType.text,
                                style: TextStyle(
                                  fontSize: 14,
                                  height:
                                      widget.fields[index].multiline ? 1.8 : 1.4,
                                ),
                                decoration: InputDecoration(
                                  hintText: widget.fields[index].hintText,
                                  helperText: widget.fields[index].helperText,
                                  helperMaxLines: 3,
                                  counterText: '',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: widget.enabled ? _save : null,
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 故事核心编辑弹层：简介 + 核心冲突 / 叙事风格 / 内容边界 / 结局基调。
Future<BlueprintStoryCore?> showStoryCoreEditSheet(
  BuildContext context,
  BlueprintStoryCore story, {
  bool enabled = true,
}) async {
  final result = await showBlueprintFieldsSheet(
    context,
    title: '编辑故事核心',
    subtitle: '故事简介是全书共同背景，最多 500 字',
    enabled: enabled,
    fields: [
      BlueprintField(
        label: '故事简介',
        value: story.summary,
        multiline: true,
        maxLength: 500,
        hintText: '写清主角是谁、核心冲突、故事走向与结局基调。',
      ),
      BlueprintField(label: '核心冲突', value: story.coreConflict, maxLength: 500),
      BlueprintField(label: '叙事风格', value: story.narrativeStyle, maxLength: 500),
      BlueprintField(label: '内容边界', value: story.contentBoundary, maxLength: 500),
      BlueprintField(label: '结局基调', value: story.endingTone, maxLength: 500),
    ],
  );
  if (result == null) return null;
  return BlueprintStoryCore(
    logline: story.logline,
    summary: result['故事简介'] ?? '',
    coreConflict: result['核心冲突'] ?? '',
    narrativeStyle: result['叙事风格'] ?? '',
    contentBoundary: result['内容边界'] ?? '',
    endingTone: result['结局基调'] ?? '',
  );
}

/// 世界与规则编辑弹层：世界观 + 规则（一行一条，`名称：内容`）+ 创作限制（一行一条）。
Future<BlueprintWorld?> showWorldEditSheet(
  BuildContext context,
  BlueprintWorld world, {
  bool enabled = true,
}) async {
  final result = await showBlueprintFieldsSheet(
    context,
    title: '编辑世界与规则',
    subtitle: '规则与限制一行一条，保存后整段替换',
    enabled: enabled,
    fields: [
      BlueprintField(
        label: '世界观',
        value: world.setting,
        multiline: true,
        hintText: '故事发生在什么时候、什么地方，有什么设定。',
      ),
      BlueprintField(
        label: '规则',
        value: world.rules
            .map((rule) => rule.detail.isEmpty
                ? rule.name
                : '${rule.name}：${rule.detail}')
            .join('\n'),
        multiline: true,
        hintText: '一行一条，例如：只有直播中的声音能被听见，录播不行。',
        helperText: '一行一条；写成「名称：内容」会保留规则名。',
      ),
      BlueprintField(
        label: '创作限制',
        value: world.constraints.join('\n'),
        multiline: true,
        hintText: '一行一条，例如：不出现血腥画面。',
      ),
    ],
  );
  if (result == null) return null;
  final rules = <BlueprintWorldRule>[];
  for (final raw in (result['规则'] ?? '').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final index = line.indexOf(RegExp(r'[：:]'));
    if (index <= 0) {
      rules.add(BlueprintWorldRule(name: line));
    } else {
      rules.add(BlueprintWorldRule(
        name: line.substring(0, index).trim(),
        detail: line.substring(index + 1).trim(),
      ));
    }
  }
  final constraints = (result['创作限制'] ?? '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  return BlueprintWorld(
    setting: result['世界观'] ?? '',
    rules: rules,
    constraints: constraints,
  );
}

/// 人物档案编辑弹层（姓名 / 身份 / 年龄 / 性别 / 外貌气质 / 性格 / 目标 / 秘密 / 成长线）。
Future<BlueprintCharacter?> showCharacterEditSheet(
  BuildContext context,
  BlueprintCharacter character, {
  bool enabled = true,
}) async {
  final result = await showBlueprintFieldsSheet(
    context,
    title: '编辑人物',
    subtitle: '人物信息会进入创作台账，写作时作为上下文',
    enabled: enabled,
    fields: [
      BlueprintField(
        label: '姓名',
        value: character.name,
        maxLength: 24,
        hintText: '姓名',
      ),
      BlueprintField(label: '身份', value: character.role, maxLength: 60),
      BlueprintField(label: '年龄', value: character.age, maxLength: 20),
      BlueprintField(label: '性别', value: character.gender, maxLength: 10),
      BlueprintField(
        label: '外貌气质',
        value: character.appearance,
        multiline: true,
      ),
      BlueprintField(label: '性格', value: character.trait, multiline: true),
      BlueprintField(label: '人物目标', value: character.goal, multiline: true),
      BlueprintField(label: '人物秘密', value: character.secret, multiline: true),
      BlueprintField(label: '成长线', value: character.growth, multiline: true),
    ],
  );
  if (result == null) return null;
  return BlueprintCharacter(
    key: character.key,
    name: (result['姓名'] ?? '').isEmpty ? character.name : result['姓名']!,
    role: result['身份'] ?? '',
    age: result['年龄'] ?? '',
    gender: result['性别'] ?? '',
    appearance: result['外貌气质'] ?? '',
    trait: result['性格'] ?? '',
    goal: result['人物目标'] ?? '',
    secret: result['人物秘密'] ?? '',
    growth: result['成长线'] ?? '',
  );
}

/// 物品编辑弹层（名称 / 件数 / 持有人 / 状态 / 外观描述）。
Future<BlueprintItem?> showItemEditSheet(
  BuildContext context,
  BlueprintItem item, {
  bool enabled = true,
}) async {
  final result = await showBlueprintFieldsSheet(
    context,
    title: '编辑物品',
    subtitle: '物品会进入创作台账，后续章节持续维护它的状态',
    enabled: enabled,
    fields: [
      BlueprintField(label: '名称', value: item.name, maxLength: 40),
      BlueprintField(label: '件数', value: item.count, maxLength: 20),
      BlueprintField(label: '持有人', value: item.owner, maxLength: 40),
      BlueprintField(label: '当前状态', value: item.state, maxLength: 200),
      BlueprintField(label: '外观与描述', value: item.desc, multiline: true),
    ],
  );
  if (result == null) return null;
  return BlueprintItem(
    key: item.key,
    name: (result['名称'] ?? '').isEmpty ? item.name : result['名称']!,
    icon: item.icon,
    desc: result['外观与描述'] ?? '',
    owner: result['持有人'] ?? '',
    count: result['件数'] ?? '',
    state: result['当前状态'] ?? '',
  );
}

/// 物品详情底部弹层：图形 / 名称 / 持有人 / 简介 / 出现轨迹 +「编辑物品」。
///
/// 返回 `'edit'` 表示用户要求编辑（由调用方打开编辑弹层并保存），其余为 null。
Future<String?> showItemDetailSheet(
  BuildContext context, {
  required BlueprintItem item,
  List<ItemAppearance> appearances = const [],
  bool canEdit = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              height: 4,
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ItemArtwork(
                          icon: item.glyphIcon,
                          name: item.name,
                          size: 92,
                          radius: 12,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text1)),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  '关键物品',
                                  if (item.owner.isNotEmpty) '${item.owner}持有',
                                  if (item.count.isNotEmpty) '共 ${item.count} 件',
                                ].join(' · '),
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.text3),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.desc.isEmpty ? '暂无物品描述。' : item.desc,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.7,
                                    color: AppColors.text2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('出现轨迹',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1)),
                    const SizedBox(height: 8),
                    if (appearances.isEmpty)
                      Text(
                        item.state.isEmpty
                            ? '尚未记录出场章节，可让 AI 整理本章资料后自动补齐。'
                            : item.state,
                        style: const TextStyle(
                            fontSize: 12, height: 1.7, color: AppColors.text3),
                      )
                    else
                      for (final appearance in appearances)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 7),
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: AppColors.text3,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(
                                      text: '${appearance.label}　',
                                      style: const TextStyle(
                                          color: AppColors.text1,
                                          fontWeight: FontWeight.w500),
                                    ),
                                    TextSpan(
                                        text: appearance.description.isEmpty
                                            ? '本章出场'
                                            : appearance.description),
                                  ]),
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.7,
                                      color: AppColors.text2),
                                ),
                              ),
                            ],
                          ),
                        ),
                    if (canEdit) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop('edit'),
                        child: const Text('编辑物品'),
                      ),
                    ],
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

/// 人物档案页的「编辑」入口复用的文本弹层（一句话简介等随笔字段）。
Future<String?> showSingleTextEditSheet(
  BuildContext context, {
  required String title,
  required String value,
  String? hintText,
  String? helperText,
  int minLines = 3,
  bool enabled = true,
}) =>
    showBlueprintTextEditSheet(
      context,
      title: title,
      initialValue: value,
      hintText: hintText,
      helperText: helperText,
      minLines: minLines,
      enabled: enabled,
    );
