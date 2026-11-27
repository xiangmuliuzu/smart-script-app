import 'package:flutter/material.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';

import '../data/blueprint_models.dart';
import '../data/chapter_meta_models.dart';
import '../widgets/blueprint_edit_sheets.dart';
import '../widgets/blueprint_visuals.dart';
import '../widgets/work_storyboard_tab.dart';
import 'chapter_page_widgets.dart';

/// 章节页四个 Tab：概要 / 正文 / 分镜 / 本章资料。
///
/// 均为无状态组件：编辑状态与保存由 [ChapterWritePage] 统一管理（自动保存防抖、
/// 只读保护、返回前保存），这里只负责渲染与回调。

/// 概要 Tab：AI 起草提示 + 概要输入 + 「按这版概要写正文 →」。
class ChapterSummaryTab extends StatelessWidget {
  const ChapterSummaryTab({
    super.key,
    required this.controller,
    required this.editable,
    required this.showAiDraftedHint,
    required this.onWriteFromSummary,
  });

  final TextEditingController controller;
  final bool editable;

  /// 首次进入且本章概要由 AI 起草时展示的提示（只展示一次）。
  final bool showAiDraftedHint;
  final VoidCallback onWriteFromSummary;

  @override
  Widget build(BuildContext context) {
    final words = controller.text.replaceAll(RegExp(r'\s'), '').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        if (showAiDraftedHint)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1EEE5),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 13, color: Color(0xFF6F6248)),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'AI 已按作品资料起草，可继续改',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6F6248)),
                  ),
                ),
              ],
            ),
          ),
        TextField(
          controller: controller,
          enabled: editable,
          maxLines: null,
          minLines: 8,
          maxLength: 500,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 14, height: 1.85),
          decoration: const InputDecoration(
            hintText: '写清这一集从哪个动作接起、发生了什么、结尾留什么钩子。',
            counterText: '',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('$words / 500 字',
                style: const TextStyle(fontSize: 12, color: AppColors.text3)),
            const Spacer(),
            const Text('生成正文与分镜都会参考',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: editable ? onWriteFromSummary : null,
          child: const Text('按这版概要写正文 →'),
        ),
        if (!editable) ...[
          const SizedBox(height: 8),
          const Text(
            '作品审核中，当前为只读状态；审核结束后可继续编辑。',
            style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.text3),
          ),
        ],
      ],
    );
  }
}

/// 正文 Tab：空态卡（✦ AI 按概要创作 / 自己写）或正文编辑区。
class ChapterTextTab extends StatelessWidget {
  const ChapterTextTab({
    super.key,
    required this.controller,
    required this.editable,
    required this.started,
    required this.onStartWriting,
    required this.onAiCreate,
  });

  final TextEditingController controller;
  final bool editable;
  final bool started;
  final VoidCallback onStartWriting;
  final VoidCallback onAiCreate;

  @override
  Widget build(BuildContext context) {
    if (!started && controller.text.trim().isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 90),
        children: [
          ChapterEmptyCard(
            icon: Icons.description_outlined,
            title: '这一集还没写正文',
            description: '正文按「内容概要」来写：可以先让 AI 出第一稿，也可以自己动笔。',
            primaryLabel: '✦ AI 按概要创作',
            secondaryLabel: '自己写',
            onPrimary: editable ? onAiCreate : null,
            onSecondary: editable ? onStartWriting : null,
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.r),
            ),
            child: TextField(
              controller: controller,
              enabled: editable,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: '从概要接着往下写…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
              style: const TextStyle(
                fontSize: 15,
                height: 1.9,
                color: AppColors.text1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 90),
      ],
    );
  }
}

/// 分镜 Tab：空态卡（✦ AI 按正文拆镜 / 自己写）或分镜编辑区 + 审核状态。
class ChapterStoryboardTab extends StatelessWidget {
  const ChapterStoryboardTab({
    super.key,
    required this.workId,
    required this.controller,
    required this.editable,
    required this.started,
    required this.board,
    required this.onStartWriting,
    required this.onAiCreate,
    required this.onOpenStandalone,
    this.openingStandalone = false,
  });

  final int workId;
  final TextEditingController controller;
  final bool editable;
  final bool started;

  /// 本章已保存的分镜（来自作品分镜目录）；无分镜为 null。
  final Map<String, dynamic>? board;
  final VoidCallback onStartWriting;
  final VoidCallback onAiCreate;
  final VoidCallback onOpenStandalone;
  final bool openingStandalone;

  static final ButtonStyle _actionStyle = TextButton.styleFrom(
    minimumSize: const Size(0, 30),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    textStyle: const TextStyle(fontSize: 12),
  );

  @override
  Widget build(BuildContext context) {
    if (!started && controller.text.trim().isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 90),
        children: [
          ChapterEmptyCard(
            icon: Icons.movie_creation_outlined,
            title: '还没有分镜',
            description: '分镜跟着正文走。可以让 AI 按正文拆镜头，也可以自己逐镜写。',
            primaryLabel: '✦ AI 按正文拆镜',
            secondaryLabel: '自己写',
            onPrimary: editable ? onAiCreate : null,
            onSecondary: editable ? onStartWriting : null,
            extra: editable
                ? TextButton(
                    onPressed: openingStandalone ? null : onOpenStandalone,
                    child: const Text('打开独立分镜页'),
                  )
                : null,
          ),
        ],
      );
    }
    final status = board == null ? '' : authorStoryboardStatus(board!['status']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      children: [
        if (board != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                const Icon(Icons.movie_filter_outlined,
                    size: 15, color: AppColors.text3),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '分镜状态：$status · 保存后进入平台审核',
                    style:
                        const TextStyle(fontSize: 11.5, color: AppColors.text3),
                  ),
                ),
                TextButton(
                  onPressed: () => openAuthorStoryboard(context, workId, board!),
                  style: _actionStyle,
                  child: const Text('查看'),
                ),
                if (editable)
                  TextButton(
                    onPressed: openingStandalone ? null : onOpenStandalone,
                    style: _actionStyle,
                    child: const Text('独立分镜页'),
                  ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.r),
          ),
          child: TextField(
            controller: controller,
            enabled: editable,
            maxLines: null,
            minLines: 14,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: '按镜头逐行写，例如：\n01 特写｜黑暗中，红色指示灯亮起。｜缓慢推近',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
            style: const TextStyle(
              fontSize: 14,
              height: 1.85,
              color: AppColors.text1,
            ),
          ),
        ),
      ],
    );
  }
}

/// 本章资料 Tab：出场人物（横向胶囊）+ 本章物品 + 本章关系（实线/虚线图例与文字说明）。
class ChapterMetaTab extends StatelessWidget {
  const ChapterMetaTab({
    super.key,
    required this.workId,
    required this.chapterNo,
    required this.meta,
    required this.blueprint,
    required this.metaTable,
    required this.chapterTitles,
    required this.editable,
    required this.busy,
    required this.onOrganize,
    required this.onEditMeta,
  });

  final int workId;
  final int chapterNo;
  final ChapterMeta meta;
  final StoryBlueprint blueprint;

  /// 作品全部章节资料：本章物品详情里的「出现轨迹」由它汇总。
  final ChapterMetaTable metaTable;

  /// 章号 → 章节标题（轨迹展示「第 N 章 · 标题」）。
  final Map<int, String> chapterTitles;
  final bool editable;
  final bool busy;
  final VoidCallback onOrganize;
  final VoidCallback onEditMeta;

  static final ButtonStyle _actionStyle = TextButton.styleFrom(
    minimumSize: const Size(0, 30),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    foregroundColor: AppColors.text3,
    textStyle: const TextStyle(fontSize: 12),
  );

  void _openCharacter(BuildContext context, String key) {
    context.push(RoutePath.blueprintCharacterUrl(workId: workId, key: key));
  }

  /// 点击本章物品：弹出物品详情（图形 / 持有人 / 简介 / 出现轨迹）。
  ///
  /// 物品详情里的「编辑物品」属于作品资料，这里只读展示（写回由作品资料页负责）。
  Future<void> _openItem(BuildContext context, String key) async {
    final item = blueprint.itemByKey(key);
    if (item == null) return;
    await showItemDetailSheet(
      context,
      item: item,
      appearances: metaTable.appearancesOfItem(key, titles: chapterTitles),
      canEdit: false,
    );
  }

  String _nameOf(String key) => blueprint.characterByKey(key)?.name ?? '';

  @override
  Widget build(BuildContext context) {
    final indexOf = {
      for (var index = 0; index < blueprint.characters.length; index++)
        blueprint.characters[index].key: index,
    };
    final relationCharacters = [
      for (final key in meta.relationKeys)
        if (blueprint.characterByKey(key) != null) blueprint.characterByKey(key)!,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        ChapterMetaCard(
          title: '出场人物',
          action: editable
              ? TextButton(
                  onPressed: busy ? null : onOrganize,
                  style: _actionStyle,
                  child: Text(busy ? '正在整理…' : 'AI 整理'),
                )
              : null,
          child: meta.cast.isEmpty
              ? const ChapterMetaEmpty('本章还没有出场人物，可由 AI 依据概要与正文整理。')
              : SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: meta.cast.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final entry = meta.cast[index];
                      return GestureDetector(
                        onTap: () => _openCharacter(context, entry.key),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Row(
                            children: [
                              CharacterAvatarChip(
                                name: entry.name,
                                index: indexOf[entry.key] ?? 0,
                                size: 26,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                entry.role.isEmpty
                                    ? entry.name
                                    : '${entry.name} · ${entry.role}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.text2),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        ChapterMetaCard(
          title: '本章物品',
          child: meta.items.isEmpty
              ? const ChapterMetaEmpty('本章还没有物品，可由 AI 依据概要与正文整理。')
              : Column(
                  children: [
                    for (final entry in meta.items)
                      _MetaItemRow(
                        entry: entry,
                        item: blueprint.itemByKey(entry.key),
                        onTap: blueprint.itemByKey(entry.key) == null
                            ? null
                            : () => _openItem(context, entry.key),
                      ),
                  ],
                ),
        ),
        ChapterMetaCard(
          title: '本章关系',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (meta.edges.isEmpty)
                const ChapterMetaEmpty('本章还没有关系变化，可由 AI 整理或手动编辑。')
              else
                RelationBoard(
                  characters: [
                    for (final character in relationCharacters)
                      RelationCharacter(
                        key: character.key,
                        name: character.name,
                        gender: character.gender,
                        index: indexOf[character.key] ?? 0,
                      ),
                  ],
                  edges: [
                    for (final edge in meta.edges)
                      RelationEdge(
                        a: edge.a,
                        b: edge.b,
                        label: edge.label,
                        dash: edge.dash,
                      ),
                  ],
                  height: 220,
                  onSelect: (key) => _openCharacter(context, key),
                  legendLeft: '这集站在一边',
                  legendRight: '这集起了疑',
                ),
              if (meta.edges.isNotEmpty)
                for (final edge in meta.edges)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${_nameOf(edge.a)} → ${_nameOf(edge.b)}',
                          style: const TextStyle(
                              color: AppColors.text1,
                              fontWeight: FontWeight.w500),
                        ),
                        TextSpan(text: '　${edge.label}'),
                      ]),
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.7,
                          color: AppColors.text2),
                    ),
                  ),
              if (editable)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy ? null : onEditMeta,
                    style: _actionStyle,
                    child: const Text('编辑本章资料'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 本章物品行：物品图形 + 名称 + 本章变化；点击查看物品详情（图形 / 持有人 / 出现轨迹）。
class _MetaItemRow extends StatelessWidget {
  const _MetaItemRow({required this.entry, required this.item, this.onTap});

  final ChapterMetaEntry entry;
  final BlueprintItem? item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = item?.name ?? entry.name;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            ItemArtwork(
              icon: item?.glyphIcon ?? guessItemIcon(name),
              name: name,
              size: 44,
              radius: 8,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text1)),
                  const SizedBox(height: 2),
                  Text(
                    entry.change.isNotEmpty
                        ? entry.change
                        : (entry.role.isEmpty ? '本章出场' : entry.role),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, height: 1.5, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}
