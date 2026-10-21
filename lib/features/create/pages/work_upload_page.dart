import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/data/bookstore_models.dart';
import '../../bookstore/data/content_providers.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../../welfare/data/welfare_providers.dart';
import '../data/author_work_providers.dart';
import '../data/create_providers.dart';

/// 新建作品（写作范式：先建一本书，再写章节）。
///
/// 只需「书名 + 分类 + 简介」即可开书（接口 2.9.2 创建）；封面、定价等资料
/// 留到作品工作台的「设置」中按需补充，减少开书门槛。创建成功后直接进入工作台。
class WorkUploadPage extends ConsumerStatefulWidget {
  const WorkUploadPage({super.key});

  @override
  ConsumerState<WorkUploadPage> createState() => _WorkUploadPageState();
}

class _WorkUploadPageState extends ConsumerState<WorkUploadPage> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  int? _categoryId;
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
    final categoryId = _categoryId;
    if (categoryId == null) {
      _toast('请选择作品分类');
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
            categoryId: categoryId,
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
    final categoriesAsync = ref.watch(categoriesProvider);
    return UserCenterScaffold(
      title: '新建作品',
      body: categoriesAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '分类加载失败，请稍后重试',
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
        data: _buildForm,
      ),
    );
  }

  Widget _buildForm(List<CategoryItem> categories) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              _Labeled(
                label: '书名',
                child: TextField(
                  controller: _titleCtrl,
                  maxLength: _titleMax,
                  decoration: const InputDecoration(
                    hintText: '请输入作品标题',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              _Labeled(
                label: '分类',
                child: DropdownButtonFormField<int>(
                  value: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    hintText: '请选择分类',
                    border: InputBorder.none,
                  ),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem<int>(
                        value: category.categoryId,
                        child: Text(category.categoryName),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
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
                    border: InputBorder.none,
                  ),
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
                : const Text('开始创作'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '提示：书名、分类与简介为必填；创建后可在作品工作台补充封面、定价等资料。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 左标签 + 右输入行。
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(label, style: const TextStyle(color: AppColors.text2)),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}