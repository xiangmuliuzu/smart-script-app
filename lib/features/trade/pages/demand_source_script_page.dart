import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';

/// 源剧本查阅页（分镜类任务）。
///
/// 接单方在付押金之前要靠它评估工作量，所以任何登录用户都能看，且正文是全本
/// ——与「验收查阅」按本轮 episodeTo 截断不同，这里不做集数裁剪。
/// 源剧本可能是发布者上传的文件（txt/pdf…），此时没有章节目录，只给下载入口。
class DemandSourceScriptPage extends ConsumerStatefulWidget {
  const DemandSourceScriptPage({super.key, required this.demandId, this.demandTitle});

  final int demandId;
  final String? demandTitle;

  @override
  ConsumerState<DemandSourceScriptPage> createState() => _DemandSourceScriptPageState();
}

class _DemandSourceScriptPageState extends ConsumerState<DemandSourceScriptPage> {
  SourceScript? _script;
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
      final script =
          await ref.read(demandRepositoryProvider).sourceScript(widget.demandId);
      if (!mounted) return;
      setState(() {
        _script = script;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError =
            e is ApiException && e.message.isNotEmpty ? e.message : '源剧本加载失败';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('源剧本')),
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
    final s = _script!;
    final hasChapters = s.chapters.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(s.title?.isNotEmpty == true ? s.title! : '源剧本',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          [
            if (s.authorName?.isNotEmpty == true) '作者 ${s.authorName}',
            if (s.episodeCount != null) '全 ${s.episodeCount} 集',
            if (s.wordCount != null) '${s.wordCount} 字',
          ].join(' · '),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
        ),
        if (s.summary?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Text(s.summary!,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.6)),
        ],
        const SizedBox(height: 10),
        if (s.hasFile) _buildFileBlock(s),
        if (!hasChapters && !s.hasFile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('发布者没有提供可读的源剧本内容，请先联系发布者确认。',
                style: TextStyle(
                    fontSize: 12, color: Colors.orange.shade800, height: 1.4)),
          )
        else if (hasChapters)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('接单前请通读源剧本评估工作量；接单后按任务轮次逐轮交付分镜。',
                style:
                    TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.4)),
          ),
        const SizedBox(height: 14),
        ...s.chapters.map(_buildChapter),
      ],
    );
  }

  /// 上传的剧本文件：走 /profile/** 静态资源，按当前 baseUrl 归一后用外部应用打开。
  Widget _buildFileBlock(SourceScript s) {
    final url = AppConfig.resolveAssetUrl(s.fileUrl!);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.fileName?.isNotEmpty == true ? s.fileName! : '剧本文件',
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _openFile(url),
            child: const Text('打开', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(const SnackBar(content: Text('剧本文件地址无效')));
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('无法打开剧本文件')));
    }
  }

  /// 单集条目：源剧本全本可读，统一用可展开的正文卡片。
  Widget _buildChapter(DeliverableChapter c) {
    final hasTitle = c.chapterTitle?.isNotEmpty == true;
    final title = c.chapterNo == null
        ? c.displayTitle
        : (hasTitle ? '第${c.chapterNo}集 · ${c.chapterTitle}' : '第${c.chapterNo}集');
    final words = c.wordCount == null ? '' : '${c.wordCount}字';
    final paragraphs = _paragraphs(c.content);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(canvasColor: Colors.white),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: words.isEmpty
              ? null
              : Text(words, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
                  child: SelectableText(p,
                      style: const TextStyle(fontSize: 14, height: 1.9)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _paragraphs(String? content) {
    if (content == null || content.trim().isEmpty) return const [];
    return content
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
