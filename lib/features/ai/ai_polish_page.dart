import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import 'data/ai_models.dart';
import 'data/ai_providers.dart';

/// AI 润色页（E 模块）：选择内容与风格，生成润色结果。
///
/// 对接 POST /api/v1/content/ai/polish；生成即落 sys_ai_write_record。
class AiPolishPage extends ConsumerStatefulWidget {
  const AiPolishPage({super.key});

  @override
  ConsumerState<AiPolishPage> createState() => _AiPolishPageState();
}

class _AiPolishPageState extends ConsumerState<AiPolishPage> {
  final _content = TextEditingController();

  /// 预设风格选项。
  static const _styles = ['简洁精炼', '专业正式', '文学优美', '轻松幽默', '情感细腻'];
  String? _selectedStyle;

  bool _loading = false;
  AiWriteResult? _result;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_content.text.trim().isEmpty) {
      showAppToast(context, '请先填写或粘贴需要润色的内容');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await ref.read(aiRepositoryProvider).polish(
            content: _content.text.trim(),
            style: _selectedStyle,
          );
      if (!mounted) return;
      setState(() => _result = result);
      if (result.content.isEmpty) {
        showAppToast(context, '未生成润色结果，请重试');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message);
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
    showAppToast(context, '润色结果已复制');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('AI 润色'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InputCard(
            content: _content,
            styles: _styles,
            selectedStyle: _selectedStyle,
            loading: _loading,
            onSelectStyle: (style) =>
                setState(() => _selectedStyle = (_selectedStyle == style ? null : style)),
            onGenerate: _generate,
          ),
          const SizedBox(height: 12),
          if (_result != null)
            _ResultCard(result: _result!, onCopy: _copy),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.content,
    required this.styles,
    required this.selectedStyle,
    required this.loading,
    required this.onSelectStyle,
    required this.onGenerate,
  });

  final TextEditingController content;
  final List<String> styles;
  final String? selectedStyle;
  final bool loading;
  final ValueChanged<String> onSelectStyle;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label(text: '待润色内容', required: true),
          const SizedBox(height: 8),
          TextField(
            controller: content,
            maxLines: 7,
            decoration: _inputDecoration('粘贴需要润色的正文、对话或旁白'),
          ),
          const SizedBox(height: 16),
          const _Label(text: '选择风格'),
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
                  : const Text('开始润色',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.fill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('润色结果',
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
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制润色结果'),
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
