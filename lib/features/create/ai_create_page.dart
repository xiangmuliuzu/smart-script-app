import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../ai/ai_quota_dialog.dart';
import '../welfare/data/welfare_providers.dart';
import 'data/blueprint_models.dart';
import 'data/blueprint_providers.dart';
import 'pages/blueprint_page.dart';
import 'widgets/blueprint_generation_view.dart';
import 'widgets/blueprint_setup_form.dart';

/// AI 创作页（v3 流程）：作品设定 → 生成中 → 资料确认。
///
/// 与旧版三步（大纲 / 逐章生成）的区别：
///   - 只生成作品级资料（故事核心、世界与规则、主要人物、关键物品、人物关系），
///     不生成分集大纲；章节内容全部在作品工作台里逐章生成；
///   - 生成走 `POST /content/ai/blueprint/stream`，按 SSE `event:stage` 推进 5 项进度；
///   - 生成完成后进入资料确认页，确认后才创建作品（`confirm` 返回 workId）。
///
/// 从 AI 记录点「继续这次创作」时，[draft] 里旧记录的设定会预填表单，
/// 作者重新生成资料（历史记录只作参考，不直接作为新作品的资料）。
class AiCreatePage extends ConsumerStatefulWidget {
  const AiCreatePage({super.key, this.draft});

  /// 从「AI 使用记录」带回的设定（旧版记录只带设定与大纲，用于预填表单）。
  final AiCreateDraft? draft;

  @override
  ConsumerState<AiCreatePage> createState() => _AiCreatePageState();
}

/// 旧版 AI 记录恢复时的草稿：只用于预填设定，不再承载大纲 / 章节。
class AiCreateDraft {
  const AiCreateDraft({
    this.title = '',
    this.idea = '',
    this.genre = '',
  });

  final String title;
  final String idea;
  final String genre;
}

class _AiCreatePageState extends ConsumerState<AiCreatePage> {
  final _titleCtrl = TextEditingController();
  final _ideaCtrl = TextEditingController();
  final _requirementCtrl = TextEditingController();

  final Set<String> _genres = <String>{};
  String? _model;
  int? _skillId;

  /// idle → generating → done → failed。
  String _phase = 'idle';
  BlueprintStageProgress _progress = BlueprintStageProgress.idle;
  String _error = '';
  int _sessionId = 0;
  int _generatedBytes = 0;
  bool _leaving = false;

  bool get _generating => _phase == 'generating';

  bool get _done => _phase == 'done';

  /// 剩余积分：未加载 / 加载失败时为 null（不显示成 0 误导用户）。
  int? get _quota => ref.watch(welfareAssetProvider).valueOrNull?.points.balance;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft == null) return;
    _titleCtrl.text = draft.title;
    _ideaCtrl.text = draft.idea;
    if (draft.genre.isNotEmpty) _genres.add(draft.genre);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _ideaCtrl.dispose();
    _requirementCtrl.dispose();
    super.dispose();
  }

  /// 校验设定，返回错误文案；通过返回空串。
  String _validate() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return '请输入书名';
    if (title.length > 100) return '书名最多 100 字';
    final idea = _ideaCtrl.text.trim();
    if (idea.length < BlueprintSetupForm.ideaMinLength) {
      return '故事灵感请至少写 ${BlueprintSetupForm.ideaMinLength} 个字';
    }
    if (idea.length > BlueprintSetupForm.ideaMaxLength) {
      return '故事灵感最多 ${BlueprintSetupForm.ideaMaxLength} 字';
    }
    if (_requirementCtrl.text.trim().length >
        BlueprintSetupForm.requirementMaxLength) {
      return '创作要求最多 ${BlueprintSetupForm.requirementMaxLength} 字';
    }
    return '';
  }

  String get _genreText => _genres.join('、');

  Future<void> _generate() async {
    if (_generating) return;
    final invalid = _validate();
    if (invalid.isNotEmpty) {
      showAppToast(context, invalid);
      return;
    }
    if (_quota == 0) {
      await showAiQuotaInsufficientDialog(context);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _phase = 'generating';
      _progress = BlueprintStageProgress.idle;
      _error = '';
      _generatedBytes = 0;
      _sessionId = 0;
    });
    try {
      final session = await ref.read(blueprintRepositoryProvider).generate(
            title: _titleCtrl.text.trim(),
            inspiration: _ideaCtrl.text.trim(),
            genre: _genreText,
            prompt: _requirementCtrl.text,
            skillId: _skillId,
            model: _model,
            onStage: (stage) {
              if (mounted) {
                setState(() => _progress = BlueprintStageProgress.fromStage(stage));
              }
            },
            onDelta: (delta) {
              if (mounted) setState(() => _generatedBytes += delta.length);
            },
          );
      if (!mounted) return;
      setState(() {
        _phase = 'done';
        _progress = BlueprintStageProgress.done;
        _sessionId = session.sessionId;
      });
      ref.invalidate(welfareAssetProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = 'failed';
        _error = e.message;
      });
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = 'failed';
          _error = '生成失败，请稍后重试';
        });
      }
    }
  }

  /// 生成完成后进入资料确认页（替换当前页，返回不再回到设定）。
  Future<void> _openConfirmation() async {
    if (_sessionId <= 0 || _leaving) return;
    _leaving = true;
    final router = GoRouter.of(context);
    await router.pushReplacement(RoutePath.aiBlueprintUrl(
      sessionId: _sessionId,
      title: _titleCtrl.text.trim(),
    ));
    _leaving = false;
  }

  /// 生成中返回：二次确认（已生成部分不会丢，可稍后在 AI 使用记录里找回）。
  Future<bool> _confirmLeaveGenerating() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('正在生成作品资料'),
        content: const Text('离开会停止生成；已经生成的内容不会写入作品，需要重新生成才能得到资料。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续等待'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('放弃生成'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _reset() async {
    if (_generating) return;
    setState(() {
      _phase = 'idle';
      _progress = BlueprintStageProgress.idle;
      _sessionId = 0;
      _error = '';
      _generatedBytes = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_generating,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final leave = await _confirmLeaveGenerating();
        if (!leave) return;
        setState(() => _phase = 'idle');
        if (context.mounted) GoRouter.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(switch (_phase) {
            'generating' => '生成中',
            'done' => '生成完成',
            'failed' => '生成失败',
            _ => 'AI 创作',
          }),
          actions: [
            if ((_done || _phase == 'failed') && _sessionId == 0)
              TextButton(onPressed: _reset, child: const Text('重来')),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _buildBody(),
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case 'generating':
      case 'done':
      case 'failed':
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            BlueprintGenerationView(
              title: _titleCtrl.text.trim(),
              progress: _progress,
              failed: _phase == 'failed',
              error: _error,
              onRetry: _phase == 'failed' ? _generate : null,
            ),
            if (_generating)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                child: Text(
                  _generatedBytes > 0
                      ? '已接收约 $_generatedBytes 字符资料，请保持页面在前台。'
                      : '生成过程中可以离开，但需要重新生成才会得到资料。',
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.8, color: AppColors.text3),
                ),
              ),
          ],
        );
      default:
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            BlueprintSetupForm(
              titleController: _titleCtrl,
              ideaController: _ideaCtrl,
              requirementController: _requirementCtrl,
              selectedGenres: _genres,
              onGenresChanged: (next) => setState(() {
                _genres
                  ..clear()
                  ..addAll(next);
              }),
              selectedModel: _model,
              onModelChanged: (value) => setState(() => _model = value),
              selectedSkillId: _skillId,
              onSkillChanged: (value) => setState(() => _skillId = value),
            ),
          ],
        );
    }
  }

  Widget _buildBottomBar() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_phase == 'idle') ...[
            Row(
              children: [
                const Icon(Icons.stars_rounded, size: 14, color: AppColors.text3),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _quota == null ? '积分加载中…' : '剩余 $_quota 积分',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _generate,
              child: const Text('生成作品资料'),
            ),
          ] else if (_generating)
            FilledButton(
              onPressed: null,
              child: Text(
                _progress.allDone ? '正在保存资料…' : '正在生成…',
              ),
            )
          else if (_done)
            FilledButton(
              onPressed: _openConfirmation,
              child: const Text('查看作品资料'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('修改设定'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _generate,
                    child: const Text('重新生成'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 兼容旧引用：蓝色资料弹层入口（AI 创作首页的「作品资料」快捷入口使用）。
Future<void> openWorkBlueprint(BuildContext context, int workId, {String? title}) {
  return context.push(RoutePath.aiBlueprintUrl(workId: workId, title: title));
}

/// 兼容旧引用：从资料会话打开确认页。
Future<void> openBlueprintConfirmation(
  BuildContext context, {
  required int sessionId,
  String? title,
}) {
  return context.push(RoutePath.aiBlueprintUrl(sessionId: sessionId, title: title));
}

/// 资料页本身（外部可复用）。
typedef AiBlueprintPage = BlueprintPage;
