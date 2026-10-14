import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import 'ai_quota_dialog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import 'data/ai_models.dart';
import 'data/ai_providers.dart';

/// AI 大纲页（E 模块）：输入主题/题材/风格，生成大纲并保存。
///
/// 对接 POST /api/v1/content/ai/outline；生成即落 sys_ai_request 记录，
/// 「保存结果」提供复制全文。
class AiOutlinePage extends ConsumerStatefulWidget {
  const AiOutlinePage({super.key});

  @override
  ConsumerState<AiOutlinePage> createState() => _AiOutlinePageState();
}

class _AiOutlinePageState extends ConsumerState<AiOutlinePage> {
  final _inspiration = TextEditingController();
  final _genre = TextEditingController();
  final _style = TextEditingController();

  bool _loading = false;
  AiOutlineResult? _result;

  @override
  void dispose() {
    _inspiration.dispose();
    _genre.dispose();
    _style.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_inspiration.text.trim().isEmpty) {
      showAppToast(context, '请先输入作品主题或灵感');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await ref.read(aiRepositoryProvider).outline(
            inspiration: _inspiration.text.trim(),
            genre: _genre.text.trim(),
            style: _style.text.trim(),
          );
      if (!mounted) return;
      setState(() => _result = result);
      if (!result.hasOutline) {
        showAppToast(context, '未生成大纲，请重试');
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
    showAppToast(context, '大纲已复制，可粘贴到编辑器');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('AI 大纲'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InputCard(
            inspiration: _inspiration,
            genre: _genre,
            style: _style,
            loading: _loading,
            onGenerate: _generate,
          ),
          const SizedBox(height: 12),
          if (_result != null) _ResultCard(result: _result!, onCopy: _copy),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 输入表单卡。
class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.inspiration,
    required this.genre,
    required this.style,
    required this.loading,
    required this.onGenerate,
  });

  final TextEditingController inspiration;
  final TextEditingController genre;
  final TextEditingController style;
  final bool loading;
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
          const _Label(text: '主题 / 灵感', required: true),
          const SizedBox(height: 8),
          TextField(
            controller: inspiration,
            maxLines: 4,
            decoration: _inputDecoration(
                '例如：落魄青年意外获得穿越能力，改写人生'),
          ),
          const SizedBox(height: 16),
          const _Label(text: '题材（可选）'),
          const SizedBox(height: 8),
          TextField(
            controller: genre,
            decoration: _inputDecoration('例如：都市、玄幻、悬疑'),
          ),
          const SizedBox(height: 16),
          const _Label(text: '风格（可选）'),
          const SizedBox(height: 8),
          TextField(
            controller: style,
            decoration: _inputDecoration('例如：爽文、正剧、轻松搞笑'),
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
                  : const Text('生成大纲',
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

  final AiOutlineResult result;
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
          Row(
            children: [
              const Text('生成的大纲',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const Spacer(),
              if (result.quotaUsed > 0)
                Text('消耗 ${result.quotaUsed} 次',
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
