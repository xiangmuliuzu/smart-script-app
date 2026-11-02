import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../../welfare/data/welfare_providers.dart';
import '../data/author_work_providers.dart';
import '../data/create_providers.dart';

/// 新建作品（写作范式：先建一本书，再写章节）。
///
/// 只需「书名 + 简介」即可开书（接口 2.9.2 创建）；标签墙体系下作品不再设置分类，
/// 标签在作品工作台「设置」中选择；封面、定价等资料同样在工作台补充。
/// 创建成功后直接进入工作台。
class WorkUploadPage extends ConsumerStatefulWidget {
  const WorkUploadPage({super.key});

  @override
  ConsumerState<WorkUploadPage> createState() => _WorkUploadPageState();
}

class _WorkUploadPageState extends ConsumerState<WorkUploadPage> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _submitting = false;

  /// 与后端标题上限一致的本地预校验上限（sys_work.title=100）。
  static const int _titleMax = 100;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _toast('请输入作品标题');
      return;
    }
    if (title.length > _titleMax) {
      _toast('标题不能超过 $_titleMax 个字符');
      return;
    }
    final description = _descCtrl.text.trim();
    if (description.isEmpty) {
      _toast('请输入作品简介');
      return;
    }
    if (description.length < 10) {
      _toast('简介至少10个字，让读者了解你的故事');
      return;
    }
    setState(() => _submitting = true);
    try {
      final workId = await ref.read(createRepositoryProvider).createWork(
            title: title,
            description: description,
          );
      // 上传作品成功：上报上传任务行为进度（fire-and-forget，失败静默）
      unawaited(reportTaskProgressByType(ref, 'UPLOAD'));
      // 失效整个 family（all/draft/reviewing/revision/rejected/published），
      // 避免只刷 'all' 而其它状态 Tab 的列表仍为旧数据。
      ref.invalidate(myWorksProvider);
      if (!mounted) return;
      context.pushReplacement(
        RoutePath.workWorkspaceUrl(workId: workId, title: title),
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('创建失败，请稍后重试');
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
    return UserCenterScaffold(
      title: '新建作品',
      body: _buildForm(),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.r),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            children: [
              _Labeled(
                label: '书名',
                child: TextField(
                  controller: _titleCtrl,
                  maxLength: _titleMax,
                  decoration: const InputDecoration(
                    hintText: '请输入作品标题',
                    counterText: '',
                  ),
                ),
              ),
              _Labeled(
                label: '简介 *',
                child: TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: '一句话介绍你的故事（至少10字）',
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('开始创作'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '提示：书名与简介为必填；创建后可在作品工作台补充标签、封面、定价等资料。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 标题与输入控件垂直排列，使用全局输入框样式。
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.text1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
