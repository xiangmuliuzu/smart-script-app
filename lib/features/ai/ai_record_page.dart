import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import 'data/ai_models.dart';
import 'data/ai_providers.dart';

/// AI 记录页（E 模块）：大纲 / 写作 / 润色记录查询，支持类型筛选与展开详情。
///
/// 数据源：GET /api/v1/content/ai/write-records（sys_ai_write_record）
/// 大纲生成时后端同步落一条 write_type='outline' 记录，三类记录统一从这里取，
/// 展开均展示「输入 / 输出」（不展示内部模型信息）。
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

  List<_Entry> get _visible {
    final all = <_Entry>[
      for (final r in _write)
        _Entry(
          time: r.createdAt,
          kind: r.writeType.isEmpty ? 'write' : r.writeType,
          write: r,
        ),
    ];
    all.sort((a, b) => b.time.compareTo(a.time));
    if (_filter == 'all') return all;
    return all.where((e) => e.kind == _filter).toList();
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
                    itemBuilder: (_, i) =>
                        _RecordCard(record: visible[i].write),
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
                      foregroundColor: AppColors.primary,
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
