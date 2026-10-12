import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/services/native_image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../bookstore/data/bookstore_models.dart';
import '../../bookstore/data/content_providers.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';
import '../data/create_providers.dart';

/// 工作台 Tab2：作品设置。
///
/// 标题 / 分类 / 简介 / 封面走 A 套 `PUT /users/me/works/{workId}`（updateWorkBase）；
/// 定价走 B 套 `PUT /content/works/{workId}`（updateWork，2.9.3 仅放行 price）。
/// 封面从本地选图，先经 2.9.1 上传拿到 url，保存在「保存」时随基本信息提交。
/// 编辑闸门：仅审核中锁定，其余状态（含已发布）均可保存；已发布改动后需重新提交审核。
class WorkSettingsTab extends ConsumerStatefulWidget {
  const WorkSettingsTab({super.key, required this.detail});

  final AuthorWorkDetail detail;

  @override
  ConsumerState<WorkSettingsTab> createState() => _WorkSettingsTabState();
}

class _WorkSettingsTabState extends ConsumerState<WorkSettingsTab> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _priceCtrl;
  int? _genreId;
  bool _saving = false;

  /// 封面上传中标志。
  bool _uploading = false;

  /// 暂存的封面 url（已上传但尚未随「保存」落库）。
  String? _pendingCover;

  static const int _titleMax = 100;

  /// 封面体积上限（与后端 multipart 10MB 限制留出余量）。
  static const int _coverMaxBytes = 5 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    final work = widget.detail.work;
    _titleCtrl = TextEditingController(text: work.title);
    _summaryCtrl = TextEditingController(text: work.summary ?? '');
    final price = work.price;
    _priceCtrl = TextEditingController(
      text: (price != null && price > 0) ? price.toString() : '',
    );
    _genreId = work.genreId;
    _pendingCover = work.cover;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
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
    // 解析定价：空串 = 0（免费），负数拒绝。
    final priceText = _priceCtrl.text.trim();
    final newPrice = priceText.isEmpty ? 0.0 : double.tryParse(priceText);
    if (priceText.isNotEmpty && newPrice == null) {
      _toast('定价格式不正确');
      return;
    }
    if (newPrice != null && newPrice < 0) {
      _toast('定价不能为负数');
      return;
    }

    final workId = widget.detail.work.workId;
    final oldPrice = widget.detail.work.price ?? 0.0;
    final priceChanged = (newPrice ?? 0.0) != oldPrice;
    final coverChanged = _pendingCover != widget.detail.work.cover;

    setState(() => _saving = true);
    try {
      // A 套更新基本信息（含封面，仅变化时下发）
      await ref.read(authorWorkRepositoryProvider).updateWorkBase(
            workId,
            title: title,
            summary: _summaryCtrl.text.trim(),
            genreId: _genreId,
            cover: coverChanged ? _pendingCover : null,
          );
      // B 套更新定价（仅当变化时）
      if (priceChanged) {
        await ref.read(createRepositoryProvider).updateWork(
              workId,
              price: newPrice,
            );
      }
      ref.invalidate(authorWorkDetailProvider(workId));
      ref.invalidate(myWorksProvider('all'));
      if (!mounted) return;
      _toast('保存成功');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 从本地选择封面并上传，成功后暂存 url（点「保存」才落库）。
  Future<void> _pickCover() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final picked = await NativeImagePicker.pickImage();
      if (picked == null) return;
      if (picked.sizeInBytes > _coverMaxBytes) {
        _toast('封面不能超过 5MB');
        return;
      }
      final url = await ref.read(createRepositoryProvider).uploadCoverBytes(
            bytes: picked.bytes,
            filename: picked.filename,
          );
      if (!mounted) return;
      setState(() => _pendingCover = url);
      _toast('封面已上传，保存后生效');
    } on NativeImageException catch (e) {
      _toast(e.message);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('封面上传失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.detail.work;
    final editable = work.editable;
    final categoriesAsync = ref.watch(categoriesProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (!editable)
          const _Notice(
            icon: Icons.lock_outline,
            text: '作品正在审核中，暂不可修改；请等待审核完成后再编辑。',
          ),
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              _Field(
                label: '标题',
                child: TextField(
                  controller: _titleCtrl,
                  maxLength: _titleMax,
                  enabled: editable,
                  decoration: const InputDecoration(
                    hintText: '请输入作品标题',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              _Field(
                label: '分类',
                child: categoriesAsync.when(
                  loading: () => const Text('加载中…',
                      style: TextStyle(color: AppColors.text3)),
                  error: (_, __) => const Text('分类加载失败',
                      style: TextStyle(color: AppColors.text3)),
                  data: (categories) => _CategoryDropdown(
                    categories: categories,
                    value: _genreId,
                    enabled: editable,
                    onChanged: (value) => setState(() => _genreId = value),
                  ),
                ),
              ),
              _Field(
                label: '简介',
                child: TextField(
                  controller: _summaryCtrl,
                  maxLines: 3,
                  minLines: 1,
                  enabled: editable,
                  decoration: const InputDecoration(
                    hintText: '作品简介（可留空）',
                    border: InputBorder.none,
                  ),
                ),
              ),
              _Field(
                label: '封面',
                child: InkWell(
                  onTap: (editable && !_uploading && !_saving) ? _pickCover : null,
                  child: Row(
                    children: [
                      if (_pendingCover != null && _pendingCover!.isNotEmpty)
                        WorkCover(url: _pendingCover!, width: 48, height: 64)
                      else
                        const _CoverPlaceholder(),
                      const SizedBox(width: 12),
                      if (_uploading)
                        const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Expanded(
                          child: Text(
                            editable ? '点击上传 / 更换封面' : '审核中不可修改',
                            style: const TextStyle(
                                color: AppColors.text3, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _Field(
                label: '定价',
                child: TextField(
                  controller: _priceCtrl,
                  enabled: editable,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '0 表示免费',
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
            onPressed: (editable && !_saving && !_uploading) ? _save : null,
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
    );
  }
}

/// 分类下拉（顶级分类）。
class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.categories,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final List<CategoryItem> categories;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    // 后端可能返回已不在顶级列表中的分类 id，兜底避免 Dropdown 断言失败。
    final hasValue = categories.any((c) => c.categoryId == value);
    return DropdownButtonFormField<int>(
      value: hasValue ? value : null,
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
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.warning.withOpacity(0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: AppColors.text2)),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

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

/// 封面缺省占位（无封面时显示）。
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.pageBackground,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.image_outlined,
          size: 24, color: AppColors.text3),
    );
  }
}