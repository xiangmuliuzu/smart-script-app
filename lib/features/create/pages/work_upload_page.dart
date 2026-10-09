import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/data/bookstore_models.dart';
import '../../bookstore/data/content_providers.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/create_providers.dart';

/// 上传新作品（APP 页面10，接口 2.9.1 上传 + 2.9.2 创建）。
///
/// 图片选择依赖平台原生通道且返回字节而非文件路径，与本模块统一的上传实现
/// （`MultipartFile.fromFile`）不兼容，故封面用「URL 输入框」由用户填写/粘贴；
/// 剧本文档上传保留：填写本地文件路径后调 2.9.1（type=script）展示文件名与地址。
class WorkUploadPage extends ConsumerStatefulWidget {
  const WorkUploadPage({super.key});

  @override
  ConsumerState<WorkUploadPage> createState() => _WorkUploadPageState();
}

class _WorkUploadPageState extends ConsumerState<WorkUploadPage> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();
  final _scriptPathCtrl = TextEditingController();

  int? _categoryId;
  bool _submitting = false;
  bool _uploadingScript = false;

  /// 已上传剧本文件的展示信息（接口 2.9.1 返回的 fileName / url）。
  String? _scriptName;
  String? _scriptUrl;

  /// 与后端标题上限一致的本地预校验上限（sys_work.title=100）。
  static const int _titleMax = 100;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _coverCtrl.dispose();
    _scriptPathCtrl.dispose();
    super.dispose();
  }

  Future<void> _uploadScript() async {
    final path = _scriptPathCtrl.text.trim();
    if (path.isEmpty) {
      _toast('请先填写剧本文件路径');
      return;
    }
    setState(() => _uploadingScript = true);
    try {
      final result = await ref.read(createRepositoryProvider).uploadFile(
            filePath: path,
            fileName: _baseName(path),
            type: 'script',
          );
      if (!mounted) return;
      setState(() {
        _scriptName = result.fileName;
        _scriptUrl = result.url;
      });
      _toast('剧本文件已上传');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('上传失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _uploadingScript = false);
    }
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
    double? price;
    final priceText = _priceCtrl.text.trim();
    if (priceText.isNotEmpty) {
      price = double.tryParse(priceText);
      if (price == null) {
        _toast('价格格式不正确');
        return;
      }
      if (price < 0) {
        _toast('价格不能为负数');
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      await ref.read(createRepositoryProvider).createWork(
            title: title,
            categoryId: categoryId,
            description: _descCtrl.text.trim(),
            cover: _coverCtrl.text.trim(),
            price: price,
          );
      ref.invalidate(draftListProvider(1));
      if (!mounted) return;
      _toast('作品已创建');
      context.pop();
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

  static String _baseName(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    final name = parts.isEmpty ? path : parts.last;
    return name.isEmpty ? 'script.txt' : name;
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    return UserCenterScaffold(
      title: '上传新作品',
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
        _Section(
          children: [
            _Labeled(
              label: '标题',
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
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          children: [
            _Labeled(
              label: '简介',
              child: TextField(
                controller: _descCtrl,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: '作品简介（可留空）',
                  border: InputBorder.none,
                ),
              ),
            ),
            _Labeled(
              label: '价格',
              child: TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '不填视为未定价',
                  border: InputBorder.none,
                ),
              ),
            ),
            _Labeled(
              label: '封面',
              child: TextField(
                controller: _coverCtrl,
                decoration: const InputDecoration(
                  hintText: '封面图片地址（可留空）',
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          children: [
            _Labeled(
              label: '剧本文件',
              child: TextField(
                controller: _scriptPathCtrl,
                decoration: const InputDecoration(
                  hintText: '本地文件路径（txt/doc/docx/pdf）',
                  border: InputBorder.none,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  OutlinedButton(
                    // 主题的 minimumSize 为 Size.fromHeight(44)（最小宽度无限），
                    // 在 Row 中会收到「紧约束无限宽」而崩溃，此处覆盖为有限最小宽度。
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _uploadingScript ? null : _uploadScript,
                    child: _uploadingScript
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('上传剧本文件'),
                  ),
                  const SizedBox(width: 12),
                  if (_scriptName != null)
                    Expanded(
                      child: Text(
                        _scriptName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.success, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            if (_scriptUrl != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  _scriptUrl!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.text3, fontSize: 12),
                ),
              ),
          ],
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '提示：分类与标题为必填项；封面可在其它页面选择图片后把地址填入此处。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 表单区块（白底卡片）。
class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(color: AppColors.card, child: Column(children: children));
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
            width: 84,
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