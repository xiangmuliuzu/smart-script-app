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

/// AI 写作页（E 模块）：输入提示词生成正文，支持复制、保存到草稿。
///
/// 对接 POST /api/v1/content/ai/write；生成即落 sys_ai_write_record。
class AiWritePage extends ConsumerStatefulWidget {
  const AiWritePage({super.key});

  @override
  ConsumerState<AiWritePage> createState() => _AiWritePageState();
}

class _AiWritePageState extends ConsumerState<AiWritePage> {
  final _prompt = TextEditingController();
  final _type = TextEditingController();

  bool _loading = false;
  AiWriteResult? _result;

  /// 流式输出中的实时文本（打字机效果）。
  String _streaming = '';

  @override
  void dispose() {
    _prompt.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_prompt.text.trim().isEmpty) {
      showAppToast(context, '请先输入写作提示词');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
      _streaming = '';
    });
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final result = await ref.read(aiRepositoryProvider).writeStream(
            prompt: _prompt.text.trim(),
            type: _type.text.trim(),
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
        showAppToast(context, '未生成内容，请重试');
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
    showAppToast(context, '内容已复制');
  }

  void _saveDraft() {
    // 本地无草稿箱接口，先复制并提示可粘贴到章节编辑器；
    // 后续接入章节保存接口后改为真实落草稿。
    final text = _result?.content ?? '';
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    showAppToast(context, '已复制，可粘贴到章节编辑器保存草稿');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 写作'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InputCard(
            prompt: _prompt,
            type: _type,
            loading: _loading,
            onGenerate: _generate,
          ),
          const SizedBox(height: 12),
          if (_streaming.isNotEmpty)
            _StreamingCard(text: _streaming, loading: _loading)
          else if (_result != null)
            _ResultCard(
              result: _result!,
              onCopy: _copy,
              onSaveDraft: _saveDraft,
            ),
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

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.prompt,
    required this.type,
    required this.loading,
    required this.onGenerate,
  });

  final TextEditingController prompt;
  final TextEditingController type;
  final bool loading;
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
          const _Label(text: '写作提示词', required: true),
          const SizedBox(height: 8),
          TextField(
            controller: prompt,
            maxLines: 6,
            decoration: _inputDecoration(
                '例如：写一段男主在公司年会上与前女友重逢的对手戏，台词克制、冲突强烈'),
          ),
          const SizedBox(height: 16),
          const _Label(text: '写作类型（可选）'),
          const SizedBox(height: 8),
          TextField(
            controller: type,
            decoration: _inputDecoration('例如：对话、旁白、动作描写'),
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
                  : const Text('生成内容',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.onCopy,
    required this.onSaveDraft,
  });

  final AiWriteResult result;
  final VoidCallback onCopy;
  final VoidCallback onSaveDraft;

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
          const Text('生成内容',
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: result.content.isEmpty ? null : onCopy,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('复制'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: result.content.isEmpty ? null : onSaveDraft,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('存草稿'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
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
