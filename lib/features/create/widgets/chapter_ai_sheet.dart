import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../ai/ai_quota_dialog.dart';

/// 章节页「AI 创作」弹层。
///
/// - 参考范围 chips（作品资料 / 内容概要 / 上一章）+ 写作要求 + 快捷 chips；
/// - 生成时实时预览草稿（正文走 `write/stream`，分镜走 `storyboard/stream`），
///   流中断时保留已收到的文本；
/// - 只有在用户点「插入到正文 / 应用到分镜页」时才回写，绝不静默覆盖已有内容；
/// - 「重新生成」「丢弃」只影响本次预览。
///
/// 返回用户确认的写入内容（[AiDraftApply]）；关闭弹层返回 null。
Future<AiDraftApply?> showChapterAiSheet(
  BuildContext context, {
  required AiDraftMode mode,
  required String workTitle,
  required int chapterNo,
  required String chapterTitle,
  required String chapterSummary,
  required String currentContent,
  required bool canEdit,
  required Future<String> Function({
    required String instruction,
    required bool refsWork,
    required bool refsSummary,
    required bool refsPrev,
    required void Function(String delta) onDelta,
  }) generate,
}) {
  return showModalBottomSheet<AiDraftApply>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _ChapterAiSheet(
      mode: mode,
      workTitle: workTitle,
      chapterNo: chapterNo,
      chapterTitle: chapterTitle,
      chapterSummary: chapterSummary,
      currentContent: currentContent,
      canEdit: canEdit,
      generate: generate,
    ),
  );
}

/// 弹层模式：正文 / 分镜。
enum AiDraftMode { text, storyboard }

/// 用户确认写入的内容。
class AiDraftApply {
  const AiDraftApply({required this.mode, required this.content});

  final AiDraftMode mode;
  final String content;
}

class _ChapterAiSheet extends StatefulWidget {
  const _ChapterAiSheet({
    required this.mode,
    required this.workTitle,
    required this.chapterNo,
    required this.chapterTitle,
    required this.chapterSummary,
    required this.currentContent,
    required this.canEdit,
    required this.generate,
  });

  final AiDraftMode mode;
  final String workTitle;
  final int chapterNo;
  final String chapterTitle;
  final String chapterSummary;
  final String currentContent;
  final bool canEdit;

  /// 生成草稿：流式增量通过 [onDelta] 实时回传，返回值用于收尾（内容可能为空，以预览为准）。
  final Future<String> Function({
    required String instruction,
    required bool refsWork,
    required bool refsSummary,
    required bool refsPrev,
    required void Function(String delta) onDelta,
  }) generate;

  @override
  State<_ChapterAiSheet> createState() => _ChapterAiSheetState();
}

class _ChapterAiSheetState extends State<_ChapterAiSheet> {
  final _instructionCtrl = TextEditingController();
  final _previewScroll = ScrollController();

  bool _refsWork = true;
  bool _refsSummary = true;
  bool _refsPrev = false;

  String _preview = '';
  String _error = '';
  bool _generating = false;

  bool get _isText => widget.mode == AiDraftMode.text;

  List<String> get _chips => _isText
      ? const ['加强冲突', '补充声音细节', '保持人物一致', '结尾留悬念']
      : const ['整体节奏克制', '突出声音线索', '增加一个空镜'];

  @override
  void dispose() {
    _instructionCtrl.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  void _fillChip(String chip) {
    final current = _instructionCtrl.text.trim();
    _instructionCtrl.text = current.isEmpty ? chip : '$current；$chip';
    _instructionCtrl.selection =
        TextSelection.collapsed(offset: _instructionCtrl.text.length);
  }

  Future<void> _generate() async {
    if (_generating || !widget.canEdit) return;
    setState(() {
      _generating = true;
      _preview = '';
      _error = '';
    });
    // 流式增量实时追加到预览，用户能边生成边看到草稿。
    void onDelta(String delta) {
      if (!mounted || delta.isEmpty) return;
      setState(() => _preview += delta);
      // 滚动到最新内容（本帧渲染后执行，避免使用旧的最大滚动范围）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_previewScroll.hasClients) return;
        _previewScroll.jumpTo(_previewScroll.position.maxScrollExtent);
      });
    }

    try {
      final text = await widget.generate(
        instruction: _instructionCtrl.text.trim(),
        refsWork: _refsWork,
        refsSummary: _refsSummary,
        refsPrev: _refsPrev,
        onDelta: onDelta,
      );
      if (!mounted) return;
      // 流式内容以预览为准；流没有回传增量时用最终结果兜底。
      final resolved = _preview.trim().isEmpty ? text.trim() : _preview.trim();
      setState(() {
        _preview = resolved;
        _error = resolved.isEmpty ? '本次未返回生成内容，请重试' : '';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      }
      setState(() {
        // 已收到的内容保留，方便作者手工取用。
        _error = _preview.trim().isEmpty
            ? e.message
            : '生成中断，已保留收到的内容：${e.message}';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _preview.trim().isEmpty
              ? 'AI 生成失败，请稍后重试'
              : '生成中断，已保留收到的内容';
        });
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _apply() {
    if (_preview.trim().isEmpty) return;
    Navigator.of(context).pop(
      AiDraftApply(mode: widget.mode, content: _preview),
    );
    // pop 后 setState 不安全，状态由页面侧处理。
  }

  void _discard() {
    setState(() {
      _preview = '';
      _error = '';
      _generating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final chapterLabel = widget.chapterTitle.trim().isEmpty
        ? '第 ${widget.chapterNo} 章'
        : '第 ${widget.chapterNo} 章 · ${widget.chapterTitle.trim()}';
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
                child: Text(
                  _isText ? 'AI 创作 · 章节正文' : 'AI 创作 · 章节分镜',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 3, 16, 6),
                child: Text(chapterLabel,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.text3)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_generating || _preview.isNotEmpty || _error.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _generating ? '正在生成…' : (_isText ? 'AI 草稿 · 第 ${widget.chapterNo} 章' : 'AI 分镜 · 第 ${widget.chapterNo} 章'),
            style: const TextStyle(fontSize: 12, color: AppColors.text3),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 300),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F4F0),
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
            ),
            // 生成中随流增长：新内容到达时自动滚到末尾，保证最新文字可见。
            child: SingleChildScrollView(
              controller: _previewScroll,
              child: _generating && _preview.isEmpty
                  ? const _Skeleton()
                  : SelectableText(
                      _preview,
                      style: const TextStyle(
                          fontSize: 13,
                          height: 1.85,
                          color: AppColors.text2),
                    ),
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error,
                  style: const TextStyle(
                      fontSize: 12, height: 1.6, color: AppColors.danger)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _generating || _preview.trim().isEmpty
                      ? null
                      : _apply,
                  child: Text(_isText ? '插入到正文' : '应用到分镜页'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _generating ? null : _generate,
                  child: const Text('重新生成'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _generating ? null : _discard,
                  child: const Text('丢弃'),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'AI 结果只在你确认后写入，不会直接覆盖已有内容。',
              style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.text3),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('参考范围',
            style: TextStyle(fontSize: 12, color: AppColors.text3)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _RefChip(
              label: '作品资料',
              selected: _refsWork,
              onTap: () => setState(() => _refsWork = !_refsWork),
            ),
            _RefChip(
              label: '内容概要',
              selected: _refsSummary,
              onTap: () => setState(() => _refsSummary = !_refsSummary),
            ),
            _RefChip(
              label: '上一章',
              selected: _refsPrev,
              onTap: () => setState(() => _refsPrev = !_refsPrev),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(_isText ? '写作要求' : '分镜要求',
            style: const TextStyle(fontSize: 12, color: AppColors.text3)),
        const SizedBox(height: 8),
        TextField(
          controller: _instructionCtrl,
          maxLines: 3,
          minLines: 3,
          decoration: InputDecoration(
            hintText: _isText
                ? '例如：把冲突提前，结尾更悬疑，保持人物对白自然。'
                : '例如：按本章生成 5 个分镜，标注景别与运镜。',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final chip in _chips)
              GestureDetector(
                onTap: () => _fillChip(chip),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(chip,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.text2)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.canEdit ? _generate : null,
          child: Text(_isText ? '✦ 生成正文草稿' : '✦ 生成章节分镜'),
        ),
        if (!widget.canEdit)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '作品审核中或当前账号无编辑权限，AI 创作暂不可用。',
              style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.text3),
            ),
          ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(AppRadius.rSmall),
          ),
          child: Text(
            '生成结果会先显示在这里，确认后再${_isText ? '插入正文' : '应用到分镜页'}，不会直接覆盖你的内容。',
            style: const TextStyle(
                fontSize: 11.5, height: 1.7, color: AppColors.text3),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '上下文：${_refsWork ? '作品资料' : ''}'
          '${_refsWork && _refsSummary ? ' · ' : ''}'
          '${_refsSummary ? '内容概要' : ''}'
          '${(_refsWork || _refsSummary) && _refsPrev ? ' · ' : ''}'
          '${_refsPrev ? '上一章' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.text3),
        ),
      ],
    );
  }
}

class _RefChip extends StatelessWidget {
  const _RefChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            fontSize: 12.5,
            color: selected ? Colors.white : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final width in const [1.0, 0.88, 0.62])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: FractionallySizedBox(
              widthFactor: width,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
