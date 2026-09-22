import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';

/// 提交意见反馈（规格 §8.7，契约 §1.6）。
///
/// 分类与内容长度受限（5–2000 字），服务端另有频率限制；
/// 附件按统一上传规则处理，本页提交平台上传服务返回的引用。
class FeedbackCreatePage extends ConsumerStatefulWidget {
  const FeedbackCreatePage({super.key});

  @override
  ConsumerState<FeedbackCreatePage> createState() => _FeedbackCreatePageState();
}

class _FeedbackCreatePageState extends ConsumerState<FeedbackCreatePage> {
  final _contentCtrl = TextEditingController();
  final _attachmentCtrl = TextEditingController();
  FeedbackCategory _category = FeedbackCategory.bug;
  bool _submitting = false;

  /// 与后端校验一致的长度下限/上限。
  static const int _minLength = 5;
  static const int _maxLength = 2000;

  @override
  void dispose() {
    _contentCtrl.dispose();
    _attachmentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.length < _minLength) {
      _toast('请至少输入 $_minLength 个字');
      return;
    }
    if (content.length > _maxLength) {
      _toast('内容不能超过 $_maxLength 个字');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(feedbackRepositoryProvider).create(
            category: _category.code,
            content: content,
            attachmentRef: _attachmentCtrl.text.trim(),
          );
      if (!mounted) return;
      _toast('提交成功，感谢反馈');
      context.pop(true);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('提交失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('意见反馈')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('反馈类型', style: TextStyle(color: AppColors.text2)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in FeedbackCategory.values)
                      ChoiceChip(
                        label: Text(category.label),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('反馈内容', style: TextStyle(color: AppColors.text2)),
                TextField(
                  controller: _contentCtrl,
                  maxLines: 6,
                  maxLength: _maxLength,
                  // 与 _minLength/_maxLength 常量同值，写成字面量以保持 const
                  decoration: const InputDecoration(
                    hintText: '请描述遇到的问题或建议（5-2000 字）',
                    border: InputBorder.none,
                  ),                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('附件引用（可选）', style: TextStyle(color: AppColors.text2)),
                TextField(
                  controller: _attachmentCtrl,
                  decoration: const InputDecoration(
                    hintText: '平台上传服务返回的引用',
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('提交'),
            ),
          ),
        ],
      ),
    );
  }
}
