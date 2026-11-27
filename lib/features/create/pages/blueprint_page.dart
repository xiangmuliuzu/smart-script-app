import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/services/native_image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../ai/ai_quota_dialog.dart';
import '../../welfare/data/welfare_providers.dart';
import '../data/blueprint_models.dart';
import '../data/author_work_providers.dart';
import '../data/blueprint_providers.dart';
import '../data/chapter_meta_models.dart';
import '../widgets/blueprint_edit_sheets.dart';
import '../widgets/blueprint_text_edit_sheet.dart';
import '../widgets/blueprint_visuals.dart';
import 'blueprint_sections.dart';

/// 「作品资料」页（资料确认页 + 作品资料页共用）。
///
/// 两种模式：
///   - [workId] > 0：已有作品，从工作台 / 章节页进入查看和修改资料；
///   - [sessionId] > 0：AI 刚生成的待确认会话，底部主按钮为「确认，开始创作」。
///
/// 区块严格对齐原型：封面卡 → 故事核心 → 世界与规则 → 主要人物 → 人物关系 → 关键物品。
/// 编辑真实落库：
///   - 故事核心 / 世界与规则 / 人物 / 物品 → 台账（`PUT /content/works/{workId}/ledger`）；
///   - 简介 / 封面 → 作品基本信息（`PUT /users/me/works/{workId}`）；
///   - 人物 / 关系 / 物品的重新整理 → 后端 `blueprint/regenerate`（需已确认资料会话）。
class BlueprintPage extends ConsumerStatefulWidget {
  const BlueprintPage({
    super.key,
    this.workId = 0,
    this.sessionId = 0,
    this.workTitle = '',
    this.isConfirmation = false,
  });

  final int workId;
  final int sessionId;
  final String workTitle;

  /// AI 刚生成的资料，进入即展示，底部主按钮为确认。
  final bool isConfirmation;

  @override
  ConsumerState<BlueprintPage> createState() => _BlueprintPageState();
}

class _BlueprintPageState extends ConsumerState<BlueprintPage> {
  StoryBlueprint? _blueprint;
  ChapterMetaTable _chapterMeta = ChapterMetaTable.empty;
  int _sessionId = 0;
  int _createdWorkId = 0;
  String _sessionTitle = '';
  bool _loading = true;
  bool _saving = false;
  String _error = '';
  String _busySection = '';
  bool _confirming = false;

  bool get _isConfirmation => widget.isConfirmation || _createdWorkId == 0 && widget.workId == 0;

  /// 作品 ID：待确认页确认后拿到；资料页直接用入参。
  int get _workId => _createdWorkId > 0 ? _createdWorkId : widget.workId;

  /// 已确认资料才允许走 AI 重新整理（后端只接受已确认会话的重生成）。
  bool get _canRegenerate => _blueprint?.isConfirmed == true && _sessionId > 0;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (widget.sessionId > 0) {
        final session =
            await ref.read(blueprintRepositoryProvider).session(widget.sessionId);
        if (!mounted) return;
        setState(() {
          _blueprint = session.blueprint;
          _sessionId = session.sessionId;
          _createdWorkId = session.workId;
          _sessionTitle = session.title;
          _loading = false;
        });
        return;
      }
      final repo = ref.read(blueprintRepositoryProvider);
      final latest = await ref.read(workBlueprintProvider(widget.workId).future);
      final meta = await ref
          .read(workChapterMetaProvider(widget.workId).future)
          .catchError((_) => ChapterMetaTable.empty);
      if (!mounted) return;
      setState(() {
        _blueprint = latest;
        _chapterMeta = meta;
        _loading = false;
      });
      // 会话编号：只有已确认的资料会话才能走 AI 重新整理；读取失败不影响展示。
      unawaited(repo.workSession(widget.workId).then((session) {
        if (!mounted || session == null) return;
        setState(() => _sessionId = session.sessionId);
      }).catchError((_) {}));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '资料加载失败，请稍后重试';
        _loading = false;
      });
    }
  }

  /// 保存结构化资料（转换为台账后整份写入，与 PC 创作者端共用一份数据）。
  Future<bool> _persist(StoryBlueprint next, {required String successText}) async {
    if (_workId <= 0) {
      showAppToast(context, '请先确认资料创建作品后再修改');
      return false;
    }
    setState(() => _saving = true);
    final previous = _blueprint;
    setState(() => _blueprint = next);
    try {
      await ref.read(blueprintRepositoryProvider).saveBlueprint(_workId, next);
      ref.invalidate(workLedgerProvider(_workId));
      ref.invalidate(workBlueprintProvider(_workId));
      if (mounted) showAppToast(context, successText);
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() => _blueprint = previous);
      showAppToast(context, e.message);
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      }
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _blueprint = previous);
      showAppToast(context, '保存失败，请稍后重试');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editStoryCore() async {
    final blueprint = _blueprint;
    if (blueprint == null || _saving) return;
    final next = await showStoryCoreEditSheet(context, blueprint.storyCore);
    if (next == null || !mounted) return;
    await _persist(
      blueprint.copyWith(storyCore: next),
      successText: '故事核心已保存',
    );
  }

  Future<void> _editWorld() async {
    final blueprint = _blueprint;
    if (blueprint == null || _saving) return;
    final next = await showWorldEditSheet(context, blueprint.world);
    if (next == null || !mounted) return;
    await _persist(
      blueprint.copyWith(world: next),
      successText: '世界与规则已保存',
    );
  }

  Future<void> _editItem(String key) async {
    final blueprint = _blueprint;
    final item = blueprint?.itemByKey(key);
    if (blueprint == null || item == null || _saving) return;
    final next = await showItemEditSheet(context, item);
    if (next == null || !mounted) return;
    final items = [
      for (final entry in blueprint.items)
        if (entry.key == key) next else entry,
    ];
    await _persist(
      blueprint.copyWith(items: items),
      successText: '物品资料已保存',
    );
  }

  Future<void> _openItem(String key) async {
    final blueprint = _blueprint;
    final item = blueprint?.itemByKey(key);
    if (item == null) return;
    final action = await showItemDetailSheet(
      context,
      item: item,
      appearances: _chapterMeta.appearancesOfItem(item.key),
      // 待确认资料只读：物品详情仅展示，不提供编辑入口。
      canEdit: _workId > 0 && !_saving,
    );
    if (action == 'edit' && mounted) await _editItem(key);
  }

  /// 重新整理资料（单项 / 全部）。需要已确认会话（后端拒绝未确认会话的重生成）。
  Future<void> _regenerate(String section, {String? key, String? instruction}) async {
    if (_busySection.isNotEmpty || _saving) return;
    if (!_canRegenerate) {
      showAppToast(context, '当前作品没有可用于整理的 AI 起稿会话，请直接在资料上编辑');
      return;
    }
    final quota = ref.read(welfareAssetProvider).valueOrNull;
    if (quota != null && quota.points.balance == 0) {
      await showAiQuotaInsufficientDialog(context);
      return;
    }
    final label = switch (section) {
      'storyCore' => '故事核心',
      'world' => '世界与规则',
      'characters' => '主要人物',
      'items' => '关键物品',
      'relations' => '人物关系',
      _ => '全部资料',
    };
    setState(() => _busySection = section);
    try {
      final result = await ref.read(blueprintRepositoryProvider).regenerate(
            sessionId: _sessionId,
            section: section,
            key: key,
            instruction: instruction,
          );
      if (!mounted) return;
      await _persist(
        result.blueprint.copyWith(status: 'confirmed'),
        successText: 'AI 已重新整理$label',
      );
      ref.invalidate(welfareAssetProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      } else {
        showAppToast(context, e.message);
      }
    } catch (_) {
      if (mounted) showAppToast(context, '整理失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busySection = '');
    }
  }

  /// 单项重新整理时先收集作者意见。
  Future<void> _askRegenerateInstruction(String section, {String? key}) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('让 AI 重新整理'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: '例如：冲突再提前一点，人物关系更紧张。',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('开始整理')),
        ],
      ),
    );
    final instruction = controller.text.trim();
    controller.dispose();
    if (confirmed != true || !mounted) return;
    await _regenerate(section, key: key, instruction: instruction);
  }

  Future<void> _editCoverSummary() async {
    final blueprint = _blueprint;
    if (blueprint == null || _saving || _workId <= 0) return;
    final value = await showBlueprintTextEditSheet(
      context,
      title: '编辑一句话简介',
      subtitle: '会同步到作品简介，写作时作为全书背景',
      initialValue: blueprint.storySummary,
    );
    if (value == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(blueprintRepositoryProvider).updateWorkBase(
            _workId,
            summary: value.trim(),
          );
      ref.invalidate(workBlueprintProvider(_workId));
      if (!mounted) return;
      setState(() {
        _blueprint = blueprint.copyWith(
          storyCore: blueprint.storyCore.copyWith(
            summary: value.trim(),
            logline: blueprint.storyCore.logline.isEmpty
                ? firstSentence(value.trim())
                : blueprint.storyCore.logline,
          ),
        );
      });
      showAppToast(context, '作品简介已保存');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } catch (_) {
      if (mounted) showAppToast(context, '保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeCover() async {
    if (_saving || _workId <= 0) return;
    setState(() => _saving = true);
    try {
      final picked = await NativeImagePicker.pickImage(filenamePrefix: 'cover');
      if (picked == null) return;
      final url = await ref.read(blueprintRepositoryProvider).uploadCover(
            bytes: picked.bytes,
            filename: picked.filename,
          );
      await ref.read(blueprintRepositoryProvider).updateWorkBase(_workId, cover: url);
      ref.invalidate(authorWorkDetailProvider(_workId));
      ref.invalidate(myWorksProvider);
      if (mounted) showAppToast(context, '封面已更新');
    } on NativeImageException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } catch (_) {
      if (mounted) showAppToast(context, '封面上传失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 确认资料：创建作品 → 刷新作品列表 → 替换进入作品工作台。
  Future<void> _confirm() async {
    if (_confirming || _saving) return;
    if (_createdWorkId > 0) {
      _openWorkspace(_createdWorkId);
      return;
    }
    if (_sessionId <= 0) {
      showAppToast(context, '缺少作品资料会话，请返回重新生成');
      return;
    }
    setState(() => _confirming = true);
    try {
      final workId =
          await ref.read(blueprintRepositoryProvider).confirm(_sessionId);
      if (!mounted) return;
      setState(() => _createdWorkId = workId);
      ref.invalidate(myWorksProvider);
      ref.invalidate(authorWorkDetailProvider(workId));
      ref.invalidate(workBlueprintProvider(workId));
      showAppToast(context, '作品已创建，进入工作台创作第 1 章');
      _openWorkspace(workId);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } catch (_) {
      if (mounted) showAppToast(context, '创建作品失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _openWorkspace(int workId) {
    // 优先用列表页透传的标题，其次用资料会话里的书名（两者都没有时由工作台自己拉详情）。
    final title = widget.workTitle.isNotEmpty ? widget.workTitle : _sessionTitle;
    GoRouter.of(context).pushReplacement(RoutePath.workWorkspaceUrl(
      workId: workId,
      title: title.isEmpty ? null : title,
    ));
  }

  /// 「全部」：底部弹出人物列表，点选后进入人物档案。
  Future<void> _openCharacterList(StoryBlueprint blueprint) async {
    if (blueprint.characters.isEmpty) return;
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
              child: Text('主要人物',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () =>
                    Navigator.of(sheetContext).pop(blueprint.characters[index]),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _openCharacter(picked.key);
  }

  /// 人物档案：已建作品可编辑；确认前的待确认会话只读浏览（按原型 v2，
  /// 资料确认阶段就能点人物卡 / 关系图查看立绘、三视图与人物信息）。
  void _openCharacter(String key) {
    if (_workId > 0) {
      context.push(RoutePath.blueprintCharacterUrl(workId: _workId, key: key));
      return;
    }
    if (_sessionId > 0) {
      context.push(RoutePath.blueprintCharacterUrl(
        sessionId: _sessionId,
        key: key,
      ));
      return;
    }
    showAppToast(context, '缺少作品资料，请返回重新生成');
  }

  @override
  Widget build(BuildContext context) {
    final blueprint = _blueprint;
    final confirming = _isConfirmation && _createdWorkId == 0;
    final editable = !_saving;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(confirming ? '资料确认' : '作品资料'),
        actions: [
          if (!confirming && _workId > 0)
            IconButton(
              tooltip: '人物档案',
              onPressed: blueprint == null || blueprint.characters.isEmpty
                  ? null
                  : () => _openCharacter(blueprint.characters.first.key),
              icon: const Icon(Icons.people_alt_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? BlueprintErrorBody(message: _error, onRetry: _load)
              : blueprint == null
                  ? const Center(child: Text('暂无作品资料'))
                  : _buildContent(blueprint, editable: editable),
      bottomNavigationBar: _loading || blueprint == null || _error.isNotEmpty
          ? null
          : BlueprintBottomBar(
              confirming: confirming,
              busy: _confirming,
              saving: _saving,
              onConfirm: _confirm,
              onDone: () => Navigator.of(context).maybePop(),
            ),
    );
  }

  Widget _buildContent(
    StoryBlueprint blueprint, {
    required bool editable,
  }) {
    final detail = _workId > 0
        ? ref.watch(authorWorkDetailProvider(_workId)).valueOrNull
        : null;
    final cover = detail?.work.cover ?? '';
    final title = detail?.work.title.isNotEmpty == true
        ? detail!.work.title
        : (_sessionTitle.isNotEmpty ? _sessionTitle : widget.workTitle);
    final characters = blueprint.characters;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        BlueprintCoverCard(
          cover: cover,
          title: title,
          tagline: blueprint.storySummary,
          onEditCover: _workId > 0 ? _changeCover : null,
          onEditSummary: _workId > 0 ? _editCoverSummary : null,
          busy: _saving,
        ),
        BlueprintCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlueprintSectionHeader(
                title: '故事核心',
                onEdit: editable && _workId > 0 ? _editStoryCore : null,
                onRegenerate: _canRegenerate && _busySection.isEmpty
                    ? () => _askRegenerateInstruction('storyCore')
                    : null,
                busy: _busySection == 'storyCore',
              ),
              const SizedBox(height: 10),
              BlueprintStoryCoreBody(story: blueprint.storyCore),
            ],
          ),
        ),
        BlueprintCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlueprintSectionHeader(
                title: '世界与规则',
                onEdit: editable && _workId > 0 ? _editWorld : null,
                onRegenerate: _canRegenerate && _busySection.isEmpty
                    ? () => _askRegenerateInstruction('world')
                    : null,
                busy: _busySection == 'world',
              ),
              const SizedBox(height: 10),
              BlueprintWorldBody(world: blueprint.world),
            ],
          ),
        ),
        BlueprintCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlueprintSectionHeader(
                title: '主要人物 · ${characters.length} 位',
                actionLabel: characters.isEmpty ? null : '全部',
                onAction: characters.isEmpty
                    ? null
                    : () => _openCharacterList(blueprint),
                onRegenerate: _canRegenerate && _busySection.isEmpty
                    ? () => _askRegenerateInstruction('characters')
                    : null,
                busy: _busySection == 'characters',
              ),
              const SizedBox(height: 10),
              if (characters.isEmpty)
                const BlueprintEmptyHint('还没有整理出人物，可让 AI 重新整理主要人物。')
              else
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: characters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final character = characters[index];
                      return BlueprintPersonCard(
                        character: character,
                        index: index,
                        onTap: () => _openCharacter(character.key),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        BlueprintCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlueprintSectionHeader(
                title: '人物关系',
                hint: '点人物看档案',
                onRegenerate: _canRegenerate && _busySection.isEmpty
                    ? () => _askRegenerateInstruction('relations')
                    : null,
                busy: _busySection == 'relations',
              ),
              const SizedBox(height: 10),
              RelationBoard(
            characters: [
              for (var index = 0; index < characters.length; index++)
                RelationCharacter(
                  key: characters[index].key,
                  name: characters[index].name,
                  gender: characters[index].gender,
                  index: index,
                  role: characters[index].role,
                ),
            ],
            edges: [
              for (final relation in blueprint.relations)
                RelationEdge(
                  a: relation.a,
                  b: relation.b,
                  label: relation.label,
                  dash: relation.dash,
                ),
            ],
            height: 236,
            onSelect: _openCharacter,
            emptyText: blueprint.characters.length < 2
                ? '人物不足两位，暂无可视化的人物关系。'
                : '暂无人物关系，可让 AI 重新整理人物关系后再查看。',
              ),
            ],
          ),
        ),
        BlueprintCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlueprintSectionHeader(
                title: '关键物品 · ${blueprint.items.length} 件',
                onRegenerate: _canRegenerate && _busySection.isEmpty
                    ? () => _askRegenerateInstruction('items')
                    : null,
                busy: _busySection == 'items',
              ),
              const SizedBox(height: 10),
              if (blueprint.items.isEmpty)
                const BlueprintEmptyHint('还没有整理出关键物品，可让 AI 重新整理。')
              else
                Column(
                  children: [
                    for (var index = 0;
                        index < blueprint.items.length;
                        index++)
                      BlueprintItemRow(
                        item: blueprint.items[index],
                        first: index == 0,
                        last: index == blueprint.items.length - 1,
                        onTap: () => _openItem(blueprint.items[index].key),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (_isConfirmation && _createdWorkId == 0)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
              '确认后创建作品并写入创作台账，人物、物品与关系会成为每一章创作的共同上下文。',
              style: TextStyle(
                  fontSize: 11.5, height: 1.7, color: AppColors.text3),
            ),
          ),
      ],
    );
  }
}
