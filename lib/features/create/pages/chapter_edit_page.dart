import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/create_models.dart';
import '../data/create_providers.dart';

/// 章节管理（接口文档未定义章节 CRUD 规格，按模块约定补齐，已获授权）。
///
/// 列表走作者视角接口 /content/works/{workId}/chapters/manage（不过滤 status，
/// 隐藏章节也在列），新增/编辑/删除走 POST /content/works/{workId}/chapters
/// 与 PUT/DELETE /content/chapters/{chapterId}。
///
/// 正文口径：列表不下发正文，编辑时正文留空表示不修改；无法从本页读回已存在正文。
/// 上下线：status "0"=正常（目录可见）、"1"=隐藏（目录不显示）。
class ChapterEditPage extends ConsumerStatefulWidget {
  const ChapterEditPage({super.key, required this.workId, this.title});

  final int workId;

  /// 作品标题，仅用于页面标题展示。
  final String? title;

  @override
  ConsumerState<ChapterEditPage> createState() => _ChapterEditPageState();
}

class _ChapterEditPageState extends ConsumerState<ChapterEditPage> {
  @override
  Widget build(BuildContext context) {
    final chapters = ref.watch(authorChapterListProvider(widget.workId));
    final title = widget.title;
    return UserCenterScaffold(
      title: title == null || title.isEmpty ? '章节管理' : '章节管理 · $title',
      actions: [
        IconButton(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add),
          tooltip: '新增章节',
        ),
      ],
      body: chapters.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (e, __) => ErrorView(
          message: e is ApiException ? e.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(authorChapterListProvider(widget.workId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyView(
              message: '暂无章节，点击右上角新增',
              icon: Icons.menu_book_outlined,
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 0.5, color: AppColors.divider),
            itemBuilder: (context, index) {
              final chapter = list[index];
              return _ChapterTile(
                chapter: chapter,
                onEdit: () => _openForm(chapter: chapter),
                onToggleStatus: () => _toggleStatus(chapter),
                onDelete: () => _delete(chapter),
              );
            },
          );
        },
      ),
    );
  }

  /// 打开新增/编辑表单；保存成功后刷新列表。
  Future<void> _openForm({AuthorChapterItem? chapter}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => _ChapterFormSheet(workId: widget.workId, chapter: chapter),
    );
    if (saved == true) {
      ref.invalidate(authorChapterListProvider(widget.workId));
    }
  }

  /// 切换章节上下线：status "0"=正常（目录可见），"1"=隐藏（目录不显示）。
  Future<void> _toggleStatus(AuthorChapterItem chapter) async {
    final nextStatus = chapter.isHidden ? '0' : '1';
    try {
      await ref.read(createRepositoryProvider).updateChapter(
            chapter.chapterId,
            status: nextStatus,
          );
      ref.invalidate(authorChapterListProvider(widget.workId));
      _toast(chapter.isHidden ? '已上线' : '已隐藏');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('操作失败，请稍后重试');
    }
  }

  /// 删除章节（物理删除，二次确认）。
  Future<void> _delete(AuthorChapterItem chapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除章节'),
        content: Text(
          '确认删除「${chapter.chapterTitle.isEmpty ? '第 ${chapter.chapterNo} 章' : chapter.chapterTitle}」？删除后不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(createRepositoryProvider).deleteChapter(chapter.chapterId);
      ref.invalidate(authorChapterListProvider(widget.workId));
      _toast('删除成功');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('删除失败，请稍后重试');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 章节行：章号 / 标题 / 字数 / 免费标记 / 隐藏标记 + 上下线、编辑、删除操作。
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final AuthorChapterItem chapter;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (chapter.wordCount > 0) '${chapter.wordCount} 字',
    ].join(' · ');
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        chapter.chapterTitle.isEmpty
                            ? '第 ${chapter.chapterNo} 章'
                            : '第 ${chapter.chapterNo} 章 · ${chapter.chapterTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      chapter.isFree ? '免费' : '付费',
                      style: TextStyle(
                        fontSize: 12,
                        color: chapter.isFree ? AppColors.success : AppColors.warning,
                      ),
                    ),
                    if (chapter.isHidden) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '已隐藏',
                        style: TextStyle(fontSize: 12, color: AppColors.text3),
                      ),
                    ],
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta, style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onToggleStatus,
            icon: Icon(
              chapter.isHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
              color: AppColors.text2,
            ),
            tooltip: chapter.isHidden ? '上线' : '隐藏',
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.text2),
            tooltip: '编辑',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }
}

/// 新增 / 编辑章节表单（底部弹层）。
///
/// [chapter] 为空为新增；非空为编辑（标题与免费状态回填，正文留空表示不修改）。
class _ChapterFormSheet extends ConsumerStatefulWidget {
  const _ChapterFormSheet({required this.workId, this.chapter});

  final int workId;
  final AuthorChapterItem? chapter;

  @override
  ConsumerState<_ChapterFormSheet> createState() => _ChapterFormSheetState();
}

class _ChapterFormSheetState extends ConsumerState<_ChapterFormSheet> {
  late final TextEditingController _noCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late bool _isFree;
  bool _saving = false;

  /// 与 sys_work_chapter.chapter_title varchar(100) 一致。
  static const int _titleMax = 100;

  bool get _isEdit => widget.chapter != null;

  @override
  void initState() {
    super.initState();
    final chapter = widget.chapter;
    _noCtrl = TextEditingController(text: chapter == null ? '' : '${chapter.chapterNo}');
    _titleCtrl = TextEditingController(text: chapter?.chapterTitle ?? '');
    _contentCtrl = TextEditingController();
    _isFree = chapter?.isFree ?? false;
  }

  @override
  void dispose() {
    _noCtrl.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _toast('请输入章节标题');
      return;
    }
    if (title.length > _titleMax) {
      _toast('标题不能超过 $_titleMax 个字符');
      return;
    }
    int? chapterNo;
    if (!_isEdit) {
      chapterNo = int.tryParse(_noCtrl.text.trim());
      if (chapterNo == null || chapterNo <= 0) {
        _toast('请输入正确的章节序号');
        return;
      }
    }
    final content = _contentCtrl.text.trim();
    if (!_isEdit && content.isEmpty) {
      _toast('请输入章节正文');
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(createRepositoryProvider);
      if (_isEdit) {
        await repo.updateChapter(
          widget.chapter!.chapterId,
          chapterTitle: title,
          content: content.isEmpty ? null : content,
          isFree: _isFree ? '1' : '0',
        );
      } else {
        await repo.createChapter(
          widget.workId,
          chapterNo: chapterNo!,
          chapterTitle: title,
          content: content,
          isFree: _isFree ? '1' : '0',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast(_isEdit ? '保存失败，请稍后重试' : '新增失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? '编辑章节' : '新增章节',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 12),
            if (!_isEdit) ...[
              TextField(
                controller: _noCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '章节序号',
                  hintText: '正整数，作品内唯一',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _titleCtrl,
              maxLength: _titleMax,
              decoration: const InputDecoration(
                labelText: '章节标题',
                counterText: '',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              maxLines: 6,
              minLines: 3,
              decoration: InputDecoration(
                labelText: '章节正文',
                hintText: _isEdit ? '留空表示不修改正文' : '请输入章节正文',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('设为免费章节', style: TextStyle(fontSize: 14)),
              value: _isFree,
              onChanged: (value) => setState(() => _isFree = value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? '保存' : '新增'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}