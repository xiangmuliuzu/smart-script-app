import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';

/// 全屏章节写作编辑器（番茄作家助手式）。
///
/// - [chapterId] 为 0 时新建模式，否则编辑模式。
/// - 编辑模式下从 [authorWorkDetailProvider] 读取章节标题与正文回填，
///   不通过路由参数传长文本（URL 长度有限）。
/// - 保存策略：输入停顿 3 秒自动保存（debounce）；返回 / 点「完成」时立即保存。
/// - 支持「设为试读章节」开关，随保存一并提交 isFree（走 B 套章节接口）。
/// - 作品处于审核中时 TextField 禁用，只读浏览。
class ChapterWritePage extends ConsumerStatefulWidget {
  const ChapterWritePage({
    super.key,
    required this.workId,
    this.chapterId = 0,
  });

  final int workId;
  final int chapterId;

  @override
  ConsumerState<ChapterWritePage> createState() => _ChapterWritePageState();
}

class _ChapterWritePageState extends ConsumerState<ChapterWritePage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;

  /// 当前已持久化的 chapterId（新建首次保存后更新为后端返回值）。
  int _chapterId = 0;

  /// 是否有未保存的修改。
  bool _dirty = false;

  /// 自动保存定时器（debounce 3 秒）。
  Timer? _autoSaveTimer;

  /// 是否正在保存中（避免重入）。
  bool _saving = false;

  /// 是否已从 provider 回填数据（仅编辑模式，避免覆盖用户输入）。
  bool _initialized = false;

  /// 从详情中派生的可编辑状态；详情未加载完时乐观置 true。
  bool _editable = true;

  /// 是否设为免费试读章节（随保存提交 isFree）。
  bool _isFree = false;

  @override
  void initState() {
    super.initState();
    _chapterId = widget.chapterId;
    _titleCtrl = TextEditingController();
    _contentCtrl = TextEditingController();
    _titleCtrl.addListener(_onChanged);
    _contentCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  /// 从工作台详情中回填章节标题与正文（仅编辑模式，仅首次）。
  void _tryInitFromProvider() {
    if (_initialized || _chapterId == 0) return;
    final detail = ref.read(authorWorkDetailProvider(widget.workId)).valueOrNull;
    if (detail == null) return;
    AuthorChapterItem? chapter;
    for (final c in detail.chapters) {
      if (c.chapterId == _chapterId) {
        chapter = c;
        break;
      }
    }
    if (chapter == null) return;
    _titleCtrl.text = chapter.chapterTitle;
    _contentCtrl.text = chapter.content;
    _isFree = chapter.isFree;
    _initialized = true;
  }

  /// 当前作品内最大章节序号 + 1（B 套要求 chapterNo 作品内唯一正整数）。
  int _nextChapterNo() {
    final detail = ref.read(authorWorkDetailProvider(widget.workId)).valueOrNull;
    var maxNo = 0;
    for (final chapter in detail?.chapters ?? const <AuthorChapterItem>[]) {
      if (chapter.chapterNo > maxNo) maxNo = chapter.chapterNo;
    }
    return maxNo + 1;
  }

  /// 输入变化：标记 dirty + 重置自动保存定时器。
  void _onChanged() {
    _dirty = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), _autoSave);
    setState(() {});
  }

  /// 自动保存（静默，不弹提示）。
  Future<void> _autoSave() async {
    if (_saving || !_dirty) return;
    await _save(silent: true);
  }

  /// 保存到后端。
  ///
  /// [silent] 为 true 时静默保存（自动保存），false 时显示成功提示。
  Future<bool> _save({bool silent = false}) async {
    if (!_editable) return true;
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text;

    // 新建模式：必须有标题才能创建。
    if (_chapterId == 0 && title.isEmpty) {
      if (!silent) _toast('请先填写章节标题');
      return false;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(authorWorkRepositoryProvider);
      if (_chapterId == 0) {
        _chapterId = await repo.addChapter(
          widget.workId,
          chapterNo: _nextChapterNo(),
          chapterTitle: title,
          content: content,
          isFree: _isFree,
        );
      } else {
        await repo.updateChapter(
          _chapterId,
          chapterTitle: title,
          content: content,
          isFree: _isFree,
        );
      }
      _dirty = false;
      if (!silent) _toast('已保存');
      // 刷新工作台数据源
      ref.invalidate(authorWorkDetailProvider(widget.workId));
      return true;
    } on ApiException catch (e) {
      if (!silent) _toast(e.message);
      return false;
    } catch (_) {
      if (!silent) _toast('保存失败，请稍后重试');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 返回前保存未提交内容。
  Future<void> _onBack() async {
    _autoSaveTimer?.cancel();
    if (_dirty && _editable) {
      await _save(silent: true);
    }
    if (mounted) context.pop();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 从工作台详情派生 editable 状态 + 回填编辑数据
    final detailAsync = ref.watch(authorWorkDetailProvider(widget.workId));
    final detail = detailAsync.valueOrNull;
    if (detail != null) {
      _editable = detail.work.editable;
      if (!_initialized) _tryInitFromProvider();
    }

    final isNew = _chapterId == 0;
    final appTitle = isNew ? '新建章节' : '编辑章节';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBack,
          ),
          title: Text(appTitle),
          actions: [
            if (_editable)
              TextButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final router = GoRouter.of(context);
                        final ok = await _save();
                        if (!mounted) return;
                        if (ok) router.pop();
                      },
                child: const Text('完成'),
              ),
          ],
        ),
        body: Column(
          children: [
            // 标题输入
            Container(
              color: AppColors.card,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _titleCtrl,
                enabled: _editable,
                maxLines: 1,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: '章节标题',
                  border: InputBorder.none,
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
            ),
            const Divider(height: 0.5, color: AppColors.divider),
            // 试读开关（仅可编辑状态可切换）
            if (_editable) ...[
              Container(
                color: AppColors.card,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.lock_open_outlined,
                        size: 16, color: AppColors.text3),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '设为试读章节（免费阅读）',
                        style: TextStyle(fontSize: 13, color: AppColors.text2),
                      ),
                    ),
                    Switch(
                      value: _isFree,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (value) {
                        _isFree = value;
                        _onChanged();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 0.5, color: AppColors.divider),
            ],
            // 正文输入
            Expanded(
              child: Container(
                color: AppColors.card,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _contentCtrl,
                  enabled: _editable,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '开始写作...',
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.8,
                    color: AppColors.text1,
                  ),
                ),
              ),
            ),
            // 底部状态栏
            _BottomBar(
              wordCount: _contentCtrl.text.length,
              saving: _saving,
              dirty: _dirty,
              editable: _editable,
              isFree: _isFree,
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部状态栏：字数 + 保存状态。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.wordCount,
    required this.saving,
    required this.dirty,
    required this.editable,
    required this.isFree,
  });

  final int wordCount;
  final bool saving;
  final bool dirty;
  final bool editable;
  final bool isFree;

  @override
  Widget build(BuildContext context) {
    final String status;
    final Color statusColor;
    if (!editable) {
      status = '只读';
      statusColor = AppColors.text3;
    } else if (saving) {
      status = '保存中...';
      statusColor = AppColors.warning;
    } else if (dirty) {
      status = '未保存';
      statusColor = AppColors.warning;
    } else {
      status = '已保存';
      statusColor = AppColors.success;
    }
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('$wordCount 字',
              style: const TextStyle(fontSize: 12, color: AppColors.text3)),
          if (isFree) ...[
            const SizedBox(width: 8),
            const Text('试读',
                style: TextStyle(fontSize: 11, color: AppColors.primary)),
          ],
          const Spacer(),
          Text(status, style: TextStyle(fontSize: 12, color: statusColor)),
        ],
      ),
    );
  }
}
