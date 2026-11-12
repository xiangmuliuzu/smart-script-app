import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../create/data/ai_create_session.dart';
import 'data/ai_models.dart';
import 'data/ai_providers.dart';

/// AI 记录页（E 模块）：大纲 / 写作 / 润色记录查询，支持类型筛选、展开详情与批量删除。
///
/// 数据源：GET /api/v1/content/ai/write-records（sys_ai_write_record）
/// 大纲生成时后端同步落一条 write_type='outline' 记录，三类记录统一从这里取，
/// 展开均展示「输入 / 输出」（不展示内部模型信息）。
///
/// AI 创作页生成的大纲与它之后生成的章节正文（input_prompt 带 [AI创作] 标记）
/// 在这里合并成一条「AI 创作」：展开显示设定、大纲与已生成章节；
/// 「记录管理」下按整组勾选，删除时整组一次提交给后端。
class AiRecordPage extends ConsumerStatefulWidget {
  const AiRecordPage({super.key});

  @override
  ConsumerState<AiRecordPage> createState() => _AiRecordPageState();
}

/// 统一记录条目（包装一条写作/润色/大纲记录，便于排序筛选）。
class _Entry {
  const _Entry({required this.time, required this.kind, required this.write});

  final String time;
  final String kind; // outline / write / polish
  final AiWriteRecord write;
}

class _AiRecordPageState extends ConsumerState<AiRecordPage> {
  static const _pageSize = 50;

  List<AiWriteRecord> _write = [];
  String _filter = 'all';
  bool _loading = true;
  bool _error = false;

  /// 记录管理：按组勾选（一次 AI 创作 = 大纲 + 它的章节记录）。
  bool _managing = false;
  final Set<String> _pickedGroups = <String>{};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 循环分页加载全部页。
  Future<List<T>> _loadAll<T>(
    Future<AiPageResult<T>> Function(int page) fetch,
  ) async {
    final collected = <T>[];
    var page = 1;
    while (true) {
      final result = await fetch(page);
      collected.addAll(result.list);
      if (result.list.isEmpty ||
          collected.length >= result.total ||
          result.list.length < _pageSize) {
        break;
      }
      page += 1;
    }
    return collected;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final repo = ref.read(aiRepositoryProvider);
      final write = await _loadAll<AiWriteRecord>(
          (p) => repo.writeRecords(page: p, pageSize: _pageSize));
      if (!mounted) return;
      setState(() {
        _write = write;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// 合并后的 AI 创作会话（大纲 + 章节）。
  List<AiCreateSession> get _sessions => groupAiCreateRecords(_write);

  /// 已被会话覆盖的记录 ID，避免在列表里重复出现。
  Set<int> get _sessionRecordIds =>
      {for (final s in _sessions) for (final r in s.records) r.recordId};

  List<AiWriteRecord> get _standalone =>
      _write.where((r) => !_sessionRecordIds.contains(r.recordId)).toList();

  /// 列表条目：一次 AI 创作合并成一条，其余记录各自一条。
  ///
  /// 合并条目按大纲记录参与类型筛选（大纲生成 = AI 剧本）。
  List<Object> get _visible {
    final sessions = _sessions.where((s) => _filter == 'all' || _filter == 'outline');
    final standalone = _standalone
        .where((r) => _filter == 'all' || r.writeType == _filter)
        .map((r) => _Entry(time: r.createdAt, kind: r.writeType.isEmpty ? 'write' : r.writeType, write: r));
    final all = <Object>[...sessions, ...standalone];
    all.sort((a, b) {
      final ta = a is AiCreateSession ? a.createdAt : (a as _Entry).time;
      final tb = b is AiCreateSession ? b.createdAt : (b as _Entry).time;
      return tb.compareTo(ta);
    });
    return all;
  }

  /// 记录管理：按组勾选。单条记录是一个只有自己的「组」。
  String _groupIdOf(Object item) =>
      item is AiCreateSession ? item.id : 'record-${(item as _Entry).write.recordId}';

  List<int> _recordIdsOf(Object item) => item is AiCreateSession
      ? item.records.map((r) => r.recordId).toList()
      : [(item as _Entry).write.recordId];

  bool get _allPicked =>
      _visible.isNotEmpty && _pickedGroups.length == _visible.length;

  void _toggleGroup(Object item) {
    final id = _groupIdOf(item);
    setState(() {
      _pickedGroups.contains(id) ? _pickedGroups.remove(id) : _pickedGroups.add(id);
    });
  }

  void _toggleAll() {
    setState(() {
      _pickedGroups.clear();
      if (!_allPicked) {
        _pickedGroups.addAll(_visible.map(_groupIdOf));
      }
    });
  }

  Future<void> _deletePicked() async {
    if (_deleting || _pickedGroups.isEmpty) return;
    final ids = <int>{
      for (final item in _visible)
        if (_pickedGroups.contains(_groupIdOf(item))) ..._recordIdsOf(item),
    }.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('删除选中的 ${_pickedGroups.length} 项记录（共 ${ids.length} 条）？'
            '删除后无法恢复，已生成的作品和章节不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(aiRepositoryProvider).deleteWriteRecords(ids);
      final removed = ids.toSet();
      setState(() {
        _write = _write.where((r) => !removed.contains(r.recordId)).toList();
        _pickedGroups.clear();
        if (_write.isEmpty) _managing = false;
      });
      if (mounted) showAppToast(context, '已删除 ${ids.length} 条记录');
    } catch (_) {
      if (mounted) showAppToast(context, '删除失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// 「继续这次创作」：按记录里的设定、大纲和已生成章节重新打开 AI 创作页。
  ///
  /// 章节只作为预览恢复到页面（不会重复落库）；继续点「进入作品工作台」时
  /// 才为新作品补建章节。参数经 extra 传递，避免把整份大纲塞进 URL。
  Future<void> _continueSession(AiCreateSession session) async {
    final setup = session.setup;
    await context.push(
      RoutePath.aiCreate,
      extra: AiCreateDraft(
        title: setup.title,
        idea: setup.idea,
        genre: setup.genre,
        episodes: setup.episodes,
        outline: session.outline,
        chapters: [
          for (final chapter in session.chapters)
            AiCreateDraftChapter(
              title: chapterTitleFromPrompt(chapter.inputPrompt),
              content: chapter.outputContent.replaceFirst(kAiCreateMark, '').trim(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 记录'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('记录加载失败',
                style: TextStyle(color: AppColors.text3, fontSize: 14)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final visible = _visible;
    return Column(
      children: [
        _FilterBar(
          current: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
        if (_write.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 8),
            child: Row(
              children: [
                Text(
                  '共 ${_sessions.length + _standalone.length} 次创作 / 记录',
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
                const Spacer(),
                if (!_managing)
                  TextButton(
                    onPressed: () => setState(() {
                      _managing = true;
                      _pickedGroups.clear();
                    }),
                    child: const Text('记录管理'),
                  )
                else ...[
                  TextButton(
                    onPressed: _deleting ? null : _toggleAll,
                    child: Text(_allPicked ? '全不选' : '全选'),
                  ),
                  TextButton(
                    onPressed: _deleting ? null : () => setState(() {
                      _managing = false;
                      _pickedGroups.clear();
                    }),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: _deleting || _pickedGroups.isEmpty ? null : _deletePicked,
                    child: Text(_deleting ? '正在删除…' : '删除所选 ${_pickedGroups.length}'),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: visible.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text('暂无记录',
                            style: TextStyle(
                                color: AppColors.text3, fontSize: 14)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final item = visible[i];
                      final picked = _pickedGroups.contains(_groupIdOf(item));
                      final content = item is AiCreateSession
                          ? _SessionCard(session: item, onContinue: _continueSession)
                          : _RecordCard(record: (item as _Entry).write);
                      if (!_managing) return content;
                      return Stack(
                        children: [
                          AbsorbPointer(child: content),
                          Positioned(
                            left: 6,
                            top: 10,
                            child: Checkbox(value: picked, onChanged: _deleting ? null : (_) => _toggleGroup(item)),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// 类型筛选条。
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('all', '全部'),
      ('outline', 'AI 剧本'),
      ('storyboard', 'AI 分镜'),
      ('write', 'AI 写作'),
      ('polish', 'AI 润色'),
    ];
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final (value, label) in options)
            _FilterChip(
              label: label,
              selected: current == value,
              onTap: () => onChanged(value),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.fill,
          borderRadius: BorderRadius.circular(16),
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

/// 记录卡（写作 / 润色 / 大纲统一样式，可展开显示输入/输出）。
class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final AiWriteRecord record;

  /// 一键复制输出内容到剪贴板。
  Future<void> _copyOutput(BuildContext context) async {
    final text = record.outputContent.isEmpty ? '' : record.outputContent;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text.isEmpty ? '输出为空，无法复制' : '已复制输出'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(
            record.title.isEmpty ? '未命名内容' : record.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text1),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                _TypeTag(record: record),
                const SizedBox(width: 8),
                Text(record.createdAt,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.text3)),
              ],
            ),
          ),
          children: [
            _Section(label: '输入', value: record.inputPrompt),
            const SizedBox(height: 10),
            _Section(label: '输出', value: record.outputContent),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text('字数 ${record.wordCount}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.text3)),
                  const SizedBox(width: 12),
                  if (record.tokensUsed > 0)
                    Text('消耗 ${record.tokensUsed} token',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.text3)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _copyOutput(context),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('复制输出'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.text1,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.record});

  final AiWriteRecord record;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (record.writeType) {
      'polish' => AppColors.warning,
      'outline' => AppColors.success,
      _ => AppColors.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        record.writeTypeLabel,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.text3,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          SelectableText(
            value.isEmpty ? '（无内容）' : value,
            style: const TextStyle(fontSize: 13, color: AppColors.text2),
          ),
        ],
      ),
    );
  }
}

/// 一次 AI 创作的合并卡片：设定 + 大纲 + 已生成章节，可「继续这次创作」。
class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onContinue});

  final AiCreateSession session;
  final ValueChanged<AiCreateSession> onContinue;

  @override
  Widget build(BuildContext context) {
    final setup = session.setup;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(
            setup.title.isEmpty ? '未命名作品' : setup.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text1),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                _SessionTypeTag(),
                const SizedBox(width: 8),
                Text(
                  '${session.chapters.length} 章',
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
                const SizedBox(width: 8),
                Text(session.createdAt, style: const TextStyle(fontSize: 12, color: AppColors.text3)),
              ],
            ),
          ),
          children: [
            _Section(label: '本次设定', value: _setupText(setup)),
            const SizedBox(height: 10),
            _Section(label: '剧本大纲', value: session.outline),
            if (session.chapters.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Section(
                label: '已生成章节',
                value: session.chapters.map((c) => chapterTitleFromPrompt(c.inputPrompt)).where((t) => t.isNotEmpty).join(kAiCreateBreak),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (session.tokens > 0)
                  Text('消耗 ${session.tokens} token', style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                const Spacer(),
                TextButton(
                  onPressed: () => onContinue(session),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.text1,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('继续这次创作'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _setupText(AiCreateSetup setup) {
    final genre = setup.genre.isEmpty ? '不限' : setup.genre;
    return '题材：$genre　集数：${setup.episodes} 集$kAiCreateBreak故事灵感：${setup.idea}';
  }
}

/// 合并会话的类型标签（统一显示「AI 创作」）。
class _SessionTypeTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(4)),
      child: const Text('AI 创作', style: TextStyle(fontSize: 11, color: AppColors.text1)),
    );
  }
}
