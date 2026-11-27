import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../data/blueprint_models.dart';
import '../data/blueprint_providers.dart';
import '../data/chapter_meta_models.dart';
import '../widgets/blueprint_edit_sheets.dart';
import '../widgets/blueprint_visuals.dart';

/// 人物档案页：头卡立绘 + 三视图 + 结构化人物信息。
///
/// 两种进入方式：
///   - [workId] > 0：已建作品（工作台 / 章节页进入），资料可编辑并写回台账；
///   - [sessionId] > 0：AI 刚生成、尚未确认的资料（资料确认页进入），只读浏览，
///     确认建作品后再从作品进入即可编辑。
///
/// 数据来自作品资料（[workBlueprintProvider]）或待确认会话（[blueprintSessionProvider]）；
/// 三视图用 Flutter 自绘线稿呈现（后端没有人物生图接口，不虚构生成能力）。
class CharacterProfilePage extends ConsumerStatefulWidget {
  const CharacterProfilePage({
    super.key,
    this.workId = 0,
    this.sessionId = 0,
    required this.characterKey,
  });

  final int workId;
  final int sessionId;
  final String characterKey;

  @override
  ConsumerState<CharacterProfilePage> createState() =>
      _CharacterProfilePageState();
}

class _CharacterProfilePageState extends ConsumerState<CharacterProfilePage> {
  bool _saving = false;
  bool _switching = false;

  /// 已建作品才能编辑（待确认资料只读）。
  bool get _canEdit => widget.workId > 0;

  /// 资料数据源：作品资料视图 / 待确认会话。
  AsyncValue<StoryBlueprint> get _blueprintAsync => widget.workId > 0
      ? ref.watch(workBlueprintProvider(widget.workId))
      : ref.watch(blueprintSessionProvider(widget.sessionId)).whenData(
            (session) => session.blueprint,
          );

  Future<void> _edit(
    StoryBlueprint blueprint,
    BlueprintCharacter character,
  ) async {
    if (_saving) return;
    final next = await showCharacterEditSheet(context, character);
    if (next == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final characters = [
        for (final entry in blueprint.characters)
          if (entry.key == character.key) next else entry,
      ];
      await ref.read(blueprintRepositoryProvider).saveBlueprint(
            widget.workId,
            blueprint.copyWith(characters: characters),
          );
      ref.invalidate(workBlueprintProvider(widget.workId));
      ref.invalidate(workLedgerProvider(widget.workId));
      if (mounted) showAppToast(context, '人物资料已保存');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } catch (_) {
      if (mounted) showAppToast(context, '保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 顶部「切换人物」：在作品人物之间快速跳转。
  Future<void> _switchCharacter(StoryBlueprint blueprint) async {
    if (_switching || blueprint.characters.length < 2) return;
    setState(() => _switching = true);
    try {
      final picked = await showModalBottomSheet<BlueprintCharacter>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Text('切换人物',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              for (var index = 0; index < blueprint.characters.length; index++)
                ListTile(
                  leading: CharacterAvatarChip(
                    name: blueprint.characters[index].name,
                    index: index,
                    gender: blueprint.characters[index].gender,
                    size: 40,
                  ),
                  title: Text(blueprint.characters[index].name),
                  subtitle: Text(
                    blueprint.characters[index].role.isEmpty
                        ? '身份待补充'
                        : blueprint.characters[index].role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: blueprint.characters[index].key ==
                          widget.characterKey
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(blueprint.characters[index]),
                ),
            ],
          ),
        ),
      );
      if (picked == null || picked.key == widget.characterKey || !mounted) return;
      // 用新 key 重建页面状态（同一路由内切换，保留返回栈）。
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => CharacterProfilePage(
          workId: widget.workId,
          sessionId: widget.sessionId,
          characterKey: picked.key,
        ),
      ));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blueprintAsync = _blueprintAsync;
    // 待确认资料还没有章节，出场轨迹为空。
    final metaAsync = widget.workId > 0
        ? ref.watch(workChapterMetaProvider(widget.workId))
        : const AsyncValue<ChapterMetaTable>.data(ChapterMetaTable.empty);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('人物档案'),
        actions: [
          blueprintAsync.maybeWhen(
            data: (blueprint) => IconButton(
              tooltip: '切换人物',
              onPressed: blueprint.characters.length > 1
                  ? () => _switchCharacter(blueprint)
                  : null,
              icon: const Icon(Icons.swap_horiz),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: blueprintAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorBody(
          message: error is ApiException ? error.message : '人物资料加载失败',
          onRetry: () => widget.workId > 0
              ? ref.invalidate(workBlueprintProvider(widget.workId))
              : ref.invalidate(blueprintSessionProvider(widget.sessionId)),
        ),
        data: (blueprint) {
          final index = blueprint.characters
              .indexWhere((character) => character.key == widget.characterKey);
          final character =
              index >= 0 ? blueprint.characters[index] : null;
          if (character == null) {
            return const Center(
              child: Text('该人物已不在作品资料中，可返回作品资料重新整理人物。'),
            );
          }
          final meta = metaAsync.valueOrNull ?? ChapterMetaTable.empty;
          return _buildBody(blueprint, character, index < 0 ? 0 : index, meta);
        },
      ),
    );
  }

  Widget _buildBody(
    StoryBlueprint blueprint,
    BlueprintCharacter character,
    int index,
    ChapterMetaTable meta,
  ) {
    final rows = <(String, String)>[
      (
        '年龄 / 性别',
        [character.age, character.gender]
            .where((value) => value.isNotEmpty)
            .join(' / '),
      ),
      ('外貌气质', character.appearance),
      ('性格', character.trait),
      ('人物目标', character.goal),
      ('人物秘密', character.secret),
      ('成长线', character.growth),
    ];
    final appearances = meta.appearancesOfCharacter(character.key);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
      children: [
        _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CharacterPortrait(
                name: character.name,
                index: index,
                gender: character.gender,
                width: 96,
                height: 120,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text1),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Text(
                        character.role.isEmpty ? '身份待补充' : character.role,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.text2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      character.brief.isEmpty ? '人物简介待补充。' : character.brief,
                      style: const TextStyle(
                          fontSize: 12, height: 1.7, color: AppColors.text3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!_canEdit)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              '资料确认前只读；确认创建作品后可在「作品资料」里编辑人物。',
              style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.text3),
            ),
          ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Text('三视图',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1)),
                  ),
                  Text(
                    '自绘线稿 · 与资料同步',
                    style: TextStyle(fontSize: 11, color: AppColors.text3),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ThreeViewPanel(
                name: character.name,
                index: index,
                height: 150,
              ),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('人物信息',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1)),
                  ),
                  if (_canEdit)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => _edit(blueprint, character),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: AppColors.text3,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: Text(_saving ? '保存中…' : '编辑'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 78,
                        child: Text(
                          row.$1,
                          style: const TextStyle(
                              fontSize: 13, height: 1.65, color: AppColors.text3),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.$2.isEmpty ? '待补充' : row.$2,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.65,
                            color: row.$2.isEmpty
                                ? AppColors.text3
                                : AppColors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('出场轨迹',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const SizedBox(height: 8),
              if (appearances.isEmpty)
                const Text(
                  '作品中还没有记录这个人物出场的本章资料。',
                  style: TextStyle(
                      fontSize: 12, height: 1.7, color: AppColors.text3),
                )
              else
                for (final appearance in appearances)
                  _AppearanceRow(appearance: appearance),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({required this.appearance});
  final ItemAppearance appearance;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  text: '第 ${appearance.chapterNo} 章　',
                  style: const TextStyle(
                      color: AppColors.text1, fontWeight: FontWeight.w500),
                ),
                TextSpan(
                  text: appearance.description.isEmpty
                      ? '本章出场'
                      : appearance.description,
                ),
              ]),
              style: const TextStyle(
                  fontSize: 12.5, height: 1.7, color: AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
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

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              style: const TextStyle(fontSize: 13, color: AppColors.text2)),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
