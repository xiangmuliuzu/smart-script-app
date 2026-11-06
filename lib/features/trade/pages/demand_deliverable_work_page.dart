import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';

/// 验收查阅：发布者查看本轮交付作品的正文（全屏页）。
///
/// 交付作品一定未上架，读者端接口取不到，所以只能走 trade 域的 deliverable-work。
/// 正文只到本轮 episodeTo，之后的集保留标题但读不到内容，避免提前拿到后续轮次的稿子。
class DemandDeliverableWorkPage extends ConsumerStatefulWidget {
  const DemandDeliverableWorkPage({
    super.key,
    required this.demandId,
    required this.stageId,
    required this.stageOrder,
  });

  final int demandId;
  final int stageId;
  final int stageOrder;

  @override
  ConsumerState<DemandDeliverableWorkPage> createState() =>
      _DemandDeliverableWorkPageState();
}

class _DemandDeliverableWorkPageState
    extends ConsumerState<DemandDeliverableWorkPage> {
  StageDeliverableView? _view;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final view = await ref
          .read(demandRepositoryProvider)
          .stageDeliverableView(widget.demandId, widget.stageId);
      if (!mounted) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError =
            e is ApiException && e.message.isNotEmpty ? e.message : '交付内容加载失败';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text('第${widget.stageOrder}轮 · 交付内容')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _loadError != null
              ? _buildErrorView()
              : _buildContentView(),
    );
  }

  Widget _buildErrorView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_loadError!,
                    style: TextStyle(
                        fontSize: 12, color: Colors.red.shade600, height: 1.4)),
              ),
              TextButton(
                  onPressed: _load,
                  child: const Text('重试', style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContentView() {
    final v = _view!;
    final chapters = v.chapters;
    // 后端 episodeTo 为空表示该轮未限定集数（整单交付），此时全本可读
    final scopeText = v.episodeTo == null
        ? '本轮未限定集数，以下 ${v.readableCount} 集均可读'
        : '本轮验收到第 ${v.episodeTo} 集，可读 ${v.readableCount} 集';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(v.title?.isNotEmpty == true ? v.title! : '作品${v.workId}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          [
            (v.authorName?.isNotEmpty == true) ? '作者 ${v.authorName}' : null,
            '全 ${v.episodeCount ?? chapters.length} 集',
            '${v.wordCount ?? 0} 字',
            if (v.aiScore != null) 'AI 审核 ${v.aiScore} 分',
          ].whereType<String>().join(' · '),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
        ),
        if (v.summary?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Text(v.summary!,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade700, height: 1.6)),
        ],
        if (v.deliverableDesc?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          _buildInfoBlock('交付说明', v.deliverableDesc!),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$scopeText。未交付的集数只列出标题，读不到正文。',
            style: TextStyle(
                fontSize: 12, color: Colors.orange.shade800, height: 1.4),
          ),
        ),
        const SizedBox(height: 14),
        if (chapters.isEmpty)
          Text('该作品暂无章节目录。',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ...chapters.map(_buildChapter),
      ],
    );
  }

  /// 交付说明等信息块（与正文区分开，避免创作者写的说明被当成稿子）。
  Widget _buildInfoBlock(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }

  /// 单集条目：可读的用 ExpansionTile 展开正文，不可读的只留一行标题。
  Widget _buildChapter(DeliverableChapter c) {
    // 没标题的集不要打成「第3集 · 第3集」，只留集号
    final hasTitle = c.chapterTitle?.isNotEmpty == true;
    final title = c.chapterNo == null
        ? c.displayTitle
        : (hasTitle ? '第${c.chapterNo}集 · ${c.chapterTitle}' : '第${c.chapterNo}集');
    final words = c.wordCount == null ? '' : '${c.wordCount}字';
    if (!c.readable) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500)),
            ),
            Text(words.isEmpty ? '后续轮次交付' : '后续轮次交付 · $words',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    final paragraphs = _paragraphs(c.content);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Theme(
        // 去掉展开时的水波纹底色，正文页保持干净
        data: Theme.of(context).copyWith(canvasColor: Colors.white),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: words.isEmpty
              ? null
              : Text(words,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          children: [
            if (paragraphs.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('该集暂无正文内容。',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              )
            else
              ...paragraphs.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(
                    p,
                    style: const TextStyle(fontSize: 14, height: 1.9),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 后端下发的是纯文本（与送 AI 审核同一口径），按空行分段渲染，不当 HTML 解析。
  List<String> _paragraphs(String? content) {
    if (content == null || content.trim().isEmpty) return const [];
    return content
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
