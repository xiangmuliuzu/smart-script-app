import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../create/data/author_work_models.dart';
import '../create/data/author_work_providers.dart';
import '../welfare/data/welfare_providers.dart';
import 'ai_quota_dialog.dart';
import 'data/ai_models.dart';
import 'data/ai_providers.dart';
import 'data/script_outline.dart';
import 'widgets/ai_model_selector.dart';
import 'widgets/ai_skill_selector.dart';

/// 注入大纲时只取末尾若干字，避免 50 集大纲把提示词撑爆。
String _tailText(String value, int max) {
  final text = value.trim();
  return text.length <= max ? text : '……${text.substring(text.length - max)}';
}

/// AI 剧本续写页（E 模块）：在已有作品的大纲/正文基础上，接着写后面的分集。
///
/// 不是重新起稿：先选要续写的作品，读它的章节与创作台账，算出续写起点，
/// 只输出后续事件卡，已有集不重写、不重复。起稿请用「AI 创作」第 1 步。
class AiOutlinePage extends ConsumerStatefulWidget {
  const AiOutlinePage({super.key});

  @override
  ConsumerState<AiOutlinePage> createState() => _AiOutlinePageState();
}

class _AiOutlinePageState extends ConsumerState<AiOutlinePage> {
  final _inspiration = TextEditingController();
  final _episodes = TextEditingController(text: '3');
  // 「一集时长」1 / 1.5 / 2 分钟，默认 1 分钟，与 PC 用户端同一口径。
  double _episodeMinutes = 1;
  // 要续写的作品；未选不能生成（本页只做续写，起稿走 AI 创作页）。
  int? _workId;
  int? _skillId;
  String? _model;

  bool _loading = false;
  AiOutlineResult? _result;

  /// 流式输出中的实时文本（打字机效果）。
  String _streaming = '';

  @override
  void dispose() {
    _inspiration.dispose();
    _episodes.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final workId = _workId;
    if (workId == null || workId <= 0) {
      showAppToast(context, '请先选择要续写的作品');
      return;
    }
    // 续写集数是本次新增的集数，口径 1–10，与起稿页上限一致。
    final episodes = int.tryParse(_episodes.text.trim()) ?? 0;
    if (episodes < 1 || episodes > 10) {
      showAppToast(context, '续写集数需为 1–10 的整数');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
      _streaming = '';
    });
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final askText = _inspiration.text.trim();
      final minuteLabel =
          _episodeMinutes == 1.5 ? '1.5 分钟' : '${_episodeMinutes.toInt()} 分钟';
      // 读作品现状：已有正文章数与台账，作为续写起点与既定内容。
      // 读取失败（网络抖动/台账为空）只降级为「无既有内容」，不阻断本次续写。
      var chapters = const <AuthorChapterItem>[];
      try {
        chapters =
            (await ref.read(authorWorkRepositoryProvider).workDetail(workId))
                .chapters;
      } catch (_) {}
      var maxNo = 0;
      for (final chapter in chapters) {
        if (chapter.chapterNo > maxNo) maxNo = chapter.chapterNo;
      }
      var ledger = const <String, String>{};
      try {
        ledger = await ref.read(aiRepositoryProvider).workLedger(workId);
      } catch (_) {}
      // 已有大纲（跨端落在台账 outline）：既影响续写起点，也要作为既定内容注入，
      // 否则只有大纲没正文时，续写会从第 1 集重新开写。
      final existingOutline = (ledger['outline'] ?? '').trim();
      var outlineMaxNo = 0;
      for (final episode in parseScriptOutline(existingOutline)) {
        if (episode.no > outlineMaxNo) outlineMaxNo = episode.no;
      }
      final lastNo = maxNo > outlineMaxNo ? maxNo : outlineMaxNo;
      final startNo = lastNo + 1;
      final ledgerBrief = [
        if ((ledger['storySummary'] ?? '').isNotEmpty)
          '故事简介（已定内容）：\n${ledger['storySummary']}',
        if ((ledger['characters'] ?? '').isNotEmpty)
          '人物便签（已定内容）：\n${ledger['characters']}',
        if ((ledger['relations'] ?? '').isNotEmpty)
          '人物关系（已定内容）：\n${ledger['relations']}',
        if (existingOutline.isNotEmpty)
          '已有大纲（已定内容，截止第 $outlineMaxNo 集，不要重写这些集）：\n${_tailText(existingOutline, 1600)}',
      ].join('\n\n');
      final brief = [
        '这是对作品 #$workId 的一次「续写」，不是重新起稿：'
            '下面给出的故事简介、人物便签、已有大纲、已有正文章节都属于既定内容，'
            '必须沿用，不得改写、不得重写、不得重复输出。',
        '已有正文 ${chapters.length} 集，已有大纲最大集号 $lastNo 集，因此续写从第 $startNo 集开始。',
        if (ledgerBrief.isNotEmpty) ledgerBrief,
        if (askText.isNotEmpty) '你的要求：\n$askText',
        '请按下面三段输出，只输出这三段，不要额外解释：',
        '故事简介：\n沿用原简介（不要重写）。',
        '人物增补：\n只写本次新增或发生状态变化的人物，格式「姓名：变化」；没有就写「无」。',
        '分集事件卡：\n从「第$startNo集：事件名」起连续编号 $episodes 集，每集四行：\n'
            '本集事件：……\n冲突与推进：……\n结果或反转：……\n结尾钩子：……\n'
            '每集按一集 $minuteLabel 的短剧容量写：一集只承载一个场景或一次交锋，'
            '结尾钩子要具体，不写场景头、镜号、景别、运镜。',
      ].join('\n');
      final result = await ref.read(aiRepositoryProvider).outlineStream(
            inspiration: brief,
            genre: '',
            style: '续写 $episodes 集，每集 $minuteLabel',
            skillId: _skillId,
            model: _model,
            onDelta: (delta) {
              if (!mounted) return;
              setState(() => _streaming += delta);
            },
          );
      // 扣减已发生。用全局 container 失效缓存：即使用户在 AI 返回前已返回上一页
      // （页面已 dispose），AI 创作页/福利中心仍在监听，返回后即显示最新次数。
      container.invalidate(aiBalanceProvider);
      container.invalidate(welfareAssetProvider);
      if (!mounted) return;
      setState(() {
        _streaming = '';
        _result = result;
      });
      if (!result.hasOutline) {
        showAppToast(context, '未生成剧本大纲，请重试');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isQuotaInsufficientError(e)) {
        await showAiQuotaInsufficientDialog(context, message: e.message);
      } else {
        showAppToast(context, e.message);
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy() {
    final text = _result?.outlineText ?? '';
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    showAppToast(context, '剧本已复制，可粘贴到编辑器');
  }

  @override
  Widget build(BuildContext context) {
    final worksAsync = ref.watch(myWorksProvider('all'));
    final works = worksAsync.valueOrNull ?? const <AuthorWorkItem>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 剧本续写'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InputCard(
            works: works,
            workId: _workId,
            onWorkChanged: (value) => setState(() => _workId = value),
            inspiration: _inspiration,
            episodes: _episodes,
            episodeMinutes: _episodeMinutes,
            onMinutesChanged: (value) => setState(() => _episodeMinutes = value),
            loading: _loading,
            selectedSkillId: _skillId,
            onSkillChanged: (value) => setState(() => _skillId = value),
            selectedModel: _model,
            onModelChanged: (value) => setState(() => _model = value),
            onGenerate: _generate,
          ),
          const SizedBox(height: 12),
          if (_streaming.isNotEmpty)
            _StreamingCard(text: _streaming, loading: _loading)
          else if (_result != null)
            _ResultCard(result: _result!, onCopy: _copy),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 流式输出中的实时文本卡（打字机效果）。
class _StreamingCard extends StatelessWidget {
  const _StreamingCard({required this.text, required this.loading});

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (loading) const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(loading ? 'AI 生成中…' : '生成已中断，已保留内容',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
            ),
            child: SelectableText(
              text.isEmpty ? '正在接收内容…' : text,
              style: const TextStyle(
                  fontSize: 14, height: 1.6, color: AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 输入表单卡。
class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.works,
    required this.workId,
    required this.onWorkChanged,
    required this.inspiration,
    required this.episodes,
    required this.episodeMinutes,
    required this.onMinutesChanged,
    required this.loading,
    required this.selectedSkillId,
    required this.onSkillChanged,
    required this.selectedModel,
    required this.onModelChanged,
    required this.onGenerate,
  });

  final List<AuthorWorkItem> works;
  final int? workId;
  final ValueChanged<int?> onWorkChanged;
  final TextEditingController inspiration;
  final TextEditingController episodes;
  final double episodeMinutes;
  final ValueChanged<double> onMinutesChanged;
  final bool loading;
  final int? selectedSkillId;
  final ValueChanged<int?> onSkillChanged;
  final String? selectedModel;
  final ValueChanged<String?> onModelChanged;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label(text: '续写作品'),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: workId,
            isExpanded: true,
            items: [
              for (final work in works)
                DropdownMenuItem(
                  value: work.workId,
                  child: Text(
                    work.title.isEmpty ? '作品 #${work.workId}' : work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: loading ? null : onWorkChanged,
            decoration: _inputDecoration(
                works.isEmpty ? '还没有作品，请先到 AI 创作页新建' : '选择要接着写的作品'),
          ),
          const SizedBox(height: 16),
          const _Label(text: '你的要求'),
          const SizedBox(height: 8),
          TextField(
            controller: inspiration,
            maxLines: 4,
            decoration: _inputDecoration('续写方向，例如：下一集让男主身份暴露，别再拖节奏'),
          ),
          const SizedBox(height: 16),
          AiSkillSelector(
            selectedSkillId: selectedSkillId,
            onChanged: onSkillChanged,
            enabled: !loading,
            skillTypeFilter: 'write',
          ),
          const SizedBox(height: 16),
          AiModelSelector(
            selectedModel: selectedModel,
            onChanged: onModelChanged,
            enabled: !loading,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label(text: '续写集数'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: episodes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: _inputDecoration('3'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _durationField()),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(width: 140, child: _durationField()),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: loading ? null : onGenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.rSmall),
                ),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('续写后续分集',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  /// 「一集时长」下拉：1 / 1.5 / 2 分钟，默认 1 分钟，与 PC 用户端同一口径。
  Widget _durationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label(text: '一集时长'),
        const SizedBox(height: 8),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(AppRadius.rSmall),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: episodeMinutes,
              isDense: true,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down,
                  size: 18, color: AppColors.text2),
              style: const TextStyle(fontSize: 13, color: AppColors.text1),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 分钟')),
                DropdownMenuItem(value: 1.5, child: Text('1.5 分钟')),
                DropdownMenuItem(value: 2, child: Text('2 分钟')),
              ],
              onChanged: loading
                  ? null
                  : (value) {
                      if (value != null) onMinutesChanged(value);
                    },
            ),
          ),
        ),
      ],
    );
  }
}

/// 结果展示卡。
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onCopy});

  final AiOutlineResult result;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('生成的剧本大纲',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const Spacer(),
              if (result.quotaUsed > 0)
                Text('消耗 ${result.quotaUsed} token',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.text3)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
            ),
            child: SelectableText(
              result.hasOutline ? result.outlineText : '暂无内容',
              style: const TextStyle(
                  fontSize: 14, height: 1.6, color: AppColors.text2),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: result.hasOutline ? onCopy : null,
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text('保存（复制全文）'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text1,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(42),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
        if (required)
          const Text(' *',
              style: TextStyle(color: AppColors.danger, fontSize: 14)),
      ],
    );
  }
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.text3, fontSize: 13),
      filled: true,
      fillColor: AppColors.fill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
