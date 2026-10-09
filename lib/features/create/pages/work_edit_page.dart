import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../bookstore/data/bookstore_models.dart';
import '../../bookstore/data/content_providers.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/create_providers.dart';

/// 编辑作品（APP 页面11，接口 2.9.3）。
///
/// 后端没有「按 id 取本人作品详情」接口，初值全部由查询参数带入；
/// 后端不支持改 category_id（也不下发明细），故分类为只读展示。
class WorkEditPage extends ConsumerStatefulWidget {
  const WorkEditPage({
    super.key,
    required this.workId,
    this.title,
    this.description,
    this.price,
    this.genreId,
  });

  final int workId;
  final String? title;
  final String? description;
  final double? price;
  final int? genreId;

  @override
  ConsumerState<WorkEditPage> createState() => _WorkEditPageState();
}

class _WorkEditPageState extends ConsumerState<WorkEditPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  bool _saving = false;

  static const int _titleMax = 100;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.title ?? '');
    _descCtrl = TextEditingController(text: widget.description ?? '');
    _priceCtrl = TextEditingController(
      text: widget.price == null ? '' : widget.price!.toString(),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _toast('请输入作品标题');
      return;
    }
    if (title.length > _titleMax) {
      _toast('标题不能超过 $_titleMax 个字符');
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
    setState(() => _saving = true);
    try {
      await ref.read(createRepositoryProvider).updateWork(
            widget.workId,
            title: title,
            description: _descCtrl.text.trim(),
            price: price,
          );
      ref.invalidate(draftListProvider(1));
      if (!mounted) return;
      _toast('保存成功');
      context.pop();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <CategoryItem>[],
        );
    return UserCenterScaffold(
      title: '编辑作品',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Container(
            color: AppColors.card,
            child: Column(
              children: [
                _EditField(
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
                _EditField(
                  label: '分类',
                  child: Text(
                    _categoryLabel(categories),
                    style: const TextStyle(color: AppColors.text3),
                  ),
                ),
                _EditField(
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
                _EditField(
                  label: '价格',
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      hintText: '不填视为未定价',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: AppColors.card,
            child: Column(
              children: [
                ListTile(
                  title: const Text('查看审核状态'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    RoutePath.reviewStatusUrl(widget.workId, title: widget.title),
                  ),
                ),
                const Divider(height: 0.5, color: AppColors.divider),
                ListTile(
                  title: const Text('查看版本'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    RoutePath.workVersionsUrl(widget.workId, title: widget.title),
                  ),
                ),
                const Divider(height: 0.5, color: AppColors.divider),
                ListTile(
                  title: const Text('章节管理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    RoutePath.chapterEditUrl(widget.workId, title: widget.title),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              '分类由创建时确定，暂不支持修改；简介与价格留空表示不更新。',
              style: TextStyle(color: AppColors.text3, fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(List<CategoryItem> categories) {
    final genreId = widget.genreId;
    if (genreId == null) return '未分类（不可修改）';
    for (final category in categories) {
      if (category.categoryId == genreId) {
        return '${category.categoryName}（不可修改）';
      }
    }
    return '分类 #$genreId（不可修改）';
  }
}

class _EditField extends StatelessWidget {
  const _EditField({required this.label, required this.child});

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