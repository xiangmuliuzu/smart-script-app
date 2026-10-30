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
import 'widgets/ai_skill_selector.dart';

/// AI 分镜页（E 模块）：把剧本拆成可直接出售的分镜脚本。
///
/// 对接 POST /api/v1/content/ai/storyboard（流式 /storyboard/stream）；
/// 生成即落 sys_ai_request(capability='storyboard') + sys_ai_write_record。
/// 输入「剧本文本」+ 可选「分镜风格」+ 可选「导演(skill)」。
class AiStoryboardPage extends ConsumerStatefulWidget {
  const AiStoryboardPage({super.key});

  @override
  ConsumerState<AiStoryboardPage> createState() => _AiStoryboardPageState();
}

class _AiStoryboardPageState extends ConsumerState<AiStoryboardPage> {
  final _script = TextEditingController();

  /// 预设分镜风格选项。
  static const _styles = ['电影感', '短剧竖屏', '动漫风'];
  String? _selectedStyle;
  int? _skillId;

  bool _loading = false;
  AiWriteResult? _result;

  /// 流式输出中的实时文本（打字机效果）。
  String _streaming = '';

  @override
  void dispose() {
    _script.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_script.text.trim().isEmpty) {
      showAppToast(context, '请先填写或粘贴剧本文本');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
      _streaming = '';
    });
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final result = await ref.read(aiRepositoryProvider).storyboardStream(
            script: _script.text.trim(),
            style: _selectedStyle,
            skillId: _skillId,
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
      if (result.content.isEmpty) {
        showAppToast(context, '未生成分镜，请重试');
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
    final text = _result?.content ?? '';
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    showAppToast(context, '分镜已复制，可提交出售或粘贴到编辑器');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 分镜'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InputCard(
            script: _script,
            styles: _styles,
            selectedStyle: _selectedStyle,
            loading: _loading,
            selectedSkillId: _skillId,
            onSkillChanged: (value) => setState(() => _skillId = value),
            onSelectStyle: (style) =>
                setState(() => _selectedStyle = (_selectedStyle == style ? null : style)),
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
    required this.script,
    required this.styles,
    required this.selectedStyle,
    required this.loading,
    required this.selectedSkillId,
    required this.onSkillChanged,
    required this.onSelectStyle,
    required this.onGenerate,
  });

  final TextEditingController script;
  final List<String> styles;
  final String? selectedStyle;
  final bool loading;
  final int? selectedSkillId;
  final ValueChanged<int?> onSkillChanged;
  final ValueChanged<String> onSelectStyle;
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
          const _Label(text: '剧本文本', required: true),
          const SizedBox(height: 8),
          TextField(
            controller: script,
            maxLines: 8,
            decoration: _inputDecoration(
                '粘贴 AI 剧本或自写剧本，AI 将拆解为可出售的分镜脚本'),
          ),
          const SizedBox(height: 16),
          AiSkillSelector(
            selectedSkillId: selectedSkillId,
            onChanged: onSkillChanged,
            enabled: !loading,
            skillTypeFilter: 'storyboard',
          ),
          const SizedBox(height: 16),
          const _Label(text: '分镜风格'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in styles)
                _StyleChip(
                  label: style,
                  selected: selectedStyle == style,
                  onTap: () => onSelectStyle(style),
                ),
            ],
          ),
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
                  : const Text('生成分镜',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 结果展示卡。
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onCopy});

  final AiWriteResult result;
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
          const Text('生成的分镜脚本',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
            ),
            child: SelectableText(
              result.content.isEmpty ? '暂无内容' : result.content,
              style: const TextStyle(
                  fontSize: 14, height: 1.6, color: AppColors.text2),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: result.content.isEmpty ? null : onCopy,
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text('复制分镜（可直接出售）'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(42),
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : AppColors.text2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
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
