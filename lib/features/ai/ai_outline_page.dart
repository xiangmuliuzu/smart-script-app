import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../welfare/data/welfare_providers.dart';
import 'ai_quota_dialog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import 'data/ai_models.dart';
import 'data/ai_providers.dart';
import 'widgets/ai_model_selector.dart';
import 'widgets/ai_skill_selector.dart';

/// AI 剧本页（E 模块）：让完全不懂创作的人也能产出专业级剧本大纲。
///
/// 对接 POST /api/v1/content/ai/outline；生成即落 sys_ai_request 记录，
/// 「保存结果」提供复制全文。可选「导演(skill)」注入导演风格。
class AiOutlinePage extends ConsumerStatefulWidget {
  const AiOutlinePage({super.key});

  @override
  ConsumerState<AiOutlinePage> createState() => _AiOutlinePageState();
}

class _AiOutlinePageState extends ConsumerState<AiOutlinePage> {
  final _inspiration = TextEditingController();
  // 故事灵感讲「讲什么」，你的要求讲「怎么写」。
  final _idea = TextEditingController();
  final _genre = TextEditingController();
  final _episodes = TextEditingController(text: '12');
  // 「一集时长」1 / 1.5 / 2 分钟，默认 1 分钟，与 PC 用户端同一口径。
  double _episodeMinutes = 1;
  int? _skillId;
  String? _model;

  bool _loading = false;
  AiOutlineResult? _result;

  /// 流式输出中的实时文本（打字机效果）。
  String _streaming = '';

  @override
  void dispose() {
    _inspiration.dispose();
    _idea.dispose();
    _genre.dispose();
    _episodes.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_idea.text.trim().isEmpty && _inspiration.text.trim().isEmpty) {
      showAppToast(context, '请先填写故事灵感（或你的要求）');
      return;
    }
    // 集数口径与 PC 用户端一致：1–50 的整数（单部作品硬上限 50 集），默认 12。
    final episodes = int.tryParse(_episodes.text.trim()) ?? 0;
    if (episodes < 1 || episodes > 50) {
      showAppToast(context, '集数需为 1–50 的整数');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
      _streaming = '';
    });
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final ideaText = _idea.text.trim();
      final askText = _inspiration.text.trim();
      final brief = [
        if (ideaText.isNotEmpty) '故事灵感：\n$ideaText',
        if (askText.isNotEmpty) '写法要求：\n$askText',
      ].join('\n');
      final minuteLabel =
          _episodeMinutes == 1.5 ? '1.5 分钟' : '${_episodeMinutes.toInt()} 分钟';
      final result = await ref.read(aiRepositoryProvider).outlineStream(
            inspiration: '$brief\n'
                '请按下面格式写 $episodes 集分集事件卡，从第1集起连续编号：\n'
                '第1集：事件名\n本集事件：……\n冲突与推进：……\n'
                '结果或反转：……\n结尾钩子：……\n'
                '每集是一件完整的事（有开场、交锋、结果），结尾钩子要具体；'
                '不要写场景头、镜号、景别、运镜。\n'
                '每集按一集 $minuteLabel 的短剧容量写：一集只承载一个场景或一次交锋，'
                '不要塞进多天多地的内容。',
            genre: _genre.text.trim(),
            style: '共 $episodes 集，每集 $minuteLabel',
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
        showAiQuotaInsufficientDialog(context, message: e.message);
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 剧本'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InputCard(
            idea: _idea,
            inspiration: _inspiration,
            genre: _genre,
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
    required this.idea,
    required this.inspiration,
    required this.genre,
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

  final TextEditingController idea;
  final TextEditingController inspiration;
  final TextEditingController genre;
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
          const _Label(text: '故事灵感'),
          const SizedBox(height: 8),
          TextField(
            controller: idea,
            maxLines: 4,
            decoration: _inputDecoration('这个故事大体讲了什么：谁、在什么处境、要解决什么…'),
          ),
          const SizedBox(height: 16),
          const _Label(text: '你的要求'),
          const SizedBox(height: 8),
          TextField(
            controller: inspiration,
            maxLines: 4,
            decoration: _inputDecoration('写法上的要求，例如：节奏必须紧凑，前三集埋一个反转…'),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label(text: '题材（可选）'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: genre,
                      decoration: _inputDecoration('例如：都市情感'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 88,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label(text: '集数'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: episodes,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('12'),
                    ),
                  ],
                ),
              ),
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
                  : const Text('生成剧本大纲',
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
