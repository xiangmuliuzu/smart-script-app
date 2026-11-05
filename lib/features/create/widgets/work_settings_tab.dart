import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/services/native_image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../bookstore/data/bookstore_models.dart';
import '../../bookstore/data/content_providers.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';
import '../data/create_providers.dart';
import 'work_delete_dialog.dart';

/// 工作台 Tab2：作品设置。
///
/// 标题 / 简介 / 封面 / 标签走 A 套 `PUT /users/me/works/{workId}`（updateWorkBase），
/// 其中标签为全量覆盖（主分类 1 + 主题 2 + 角色 2 + 情节 2，最多 7 个）；标签墙体系下作品不再设置分类。
/// 定价走 B 套 `PUT /content/works/{workId}`（updateWork，2.9.3 仅放行 price）。
/// 封面从本地选图，先经 2.9.1 上传拿到 url，保存在「保存」时随基本信息提交。
/// 编辑闸门：仅审核中锁定，其余状态（含已发布）均可保存；已发布改动后需重新提交审核。
class WorkSettingsTab extends ConsumerStatefulWidget {
  const WorkSettingsTab({super.key, required this.detail});

  final AuthorWorkDetail detail;

  @override
  ConsumerState<WorkSettingsTab> createState() => _WorkSettingsTabState();
}

/// 作品标签数量上限（主分类 1 + 主题 2 + 角色 2 + 情节 2 = 最多 7 个，后端同样按 400 拒绝超限）。
const int _kMaxWorkTags = 7;

class _WorkSettingsTabState extends ConsumerState<WorkSettingsTab> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _priceCtrl;
  bool _saving = false;
  bool _deleting = false;

  /// 已选标签ID（全量覆盖提交，仅变化时下发）。
  late final Set<int> _tagIds;
  int? _pendingChannelId;

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
    _pendingCover = work.cover;
    _pendingChannelId = work.channelId;
    _tagIds = widget.detail.tags.map((tag) => tag.tagId).toSet();
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
    final oldTagIds = widget.detail.tags.map((tag) => tag.tagId).toSet();
    final tagsChanged = _tagIds.length != oldTagIds.length ||
        !_tagIds.every(oldTagIds.contains);

    setState(() => _saving = true);
    try {
      // A 套更新基本信息（含封面、标签、频道，仅变化时下发）
      await ref.read(authorWorkRepositoryProvider).updateWorkBase(
            workId,
            title: title,
            summary: _summaryCtrl.text.trim(),
            cover: coverChanged ? _pendingCover : null,
            tagIds: tagsChanged ? _tagIds.toList() : null,
            channelId: _pendingChannelId,
          );
      // B 套更新定价（仅当变化时）。A、B 是两次独立 PUT，非原子：
      // A 已落库后若 B 再失败，不能整体报「保存失败」误导用户，需分别提示。
      if (priceChanged) {
        final priceSaved = await _savePriceWithRetry(workId, newPrice ?? 0.0);
        if (!priceSaved) {
          // B 两次都失败：基本信息已保存；保留定价表单值供用户重存（PUT 幂等），
          // 不标记「未保存」，仅刷新已落库的 A 套数据。
          ref.invalidate(authorWorkDetailProvider(workId));
          ref.invalidate(myWorksProvider);
          if (!mounted) return;
          _toast('基本信息已保存，但定价/交易设置保存失败，请重试');
          return;
        }
      }
      ref.invalidate(authorWorkDetailProvider(workId));
      // 失效整个 family，覆盖 all/draft/reviewing/revision/rejected/published。
      ref.invalidate(myWorksProvider);
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

  Future<void> _deleteWork() async {
    if (_saving || _uploading || _deleting) return;
    setState(() => _deleting = true);
    final work = widget.detail.work;
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkDeleteDialog(
        workId: work.workId,
        title: work.title.isEmpty ? '未命名作品' : work.title,
      ),
    );
    if (!mounted) return;
    setState(() => _deleting = false);
    if (deleted != true) return;
    ref.invalidate(myWorksProvider);
    _toast('作品已删除');
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(RoutePath.create);
    }
  }

  /// B 套定价保存，失败自动重试一次（PUT 幂等，重试安全）。
  ///
  /// 不抛错：返回是否最终成功，由调用方据 A 套是否已落库给出准确文案。
  Future<bool> _savePriceWithRetry(int workId, double price) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await ref
            .read(createRepositoryProvider)
            .updateWork(workId, price: price);
        return true;
      } catch (_) {
        if (attempt == 0) continue;
        return false;
      }
    }
    return false;
  }

  /// 打开标签多选弹窗。
  ///
  /// 弹窗内改动的是临时集合，点「确定」才回写；点「取消」/ 下滑关闭视为放弃修改。
  Future<void> _openTagPicker(List<TagItem> tags) async {
    if (tags.isEmpty) {
      _toast('暂无可用标签');
      return;
    }
    final picked = await showModalBottomSheet<_TagPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r)),
      ),
      builder: (_) => _TagPickerSheet(
        tags: tags,
        initial: _tagIds,
        initialChannelId: _pendingChannelId ?? 146,
        maxCount: _kMaxWorkTags,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _tagIds
        ..clear()
        ..addAll(picked.tagIds);
      _pendingChannelId = picked.channelId;
    });
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

  Widget _buildChannelBtn(
      String label, int channelId, bool editable, List<TagItem> allTags) {
    final isSelected = _pendingChannelId == channelId;
    return GestureDetector(
      onTap: editable
          ? () => setState(() {
                // 切换频道时清掉不属于该频道的已选标签，避免跨频道标签混存
                if (_pendingChannelId != channelId) {
                  _tagIds.removeWhere((id) {
                    final matched = allTags.where((t) => t.tagId == id);
                    if (matched.isEmpty) return false;
                    final tag = matched.first;
                    return tag.channelId != null && tag.channelId != channelId;
                  });
                }
                _pendingChannelId = channelId;
              })
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.fill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.primary : AppColors.text2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.detail.work;
    final editable = work.editable;
    // 标签库全量启用标签（与分类页同一数据源 GET /content/tags）
    final tagsAsync = ref.watch(tagsProvider);
    final allTags = tagsAsync.valueOrNull ?? const <TagItem>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!editable)
          const _Notice(
            icon: Icons.lock_outline,
            text: '作品正在审核中，暂不可修改；请等待审核完成后再编辑。',
          ),
        // 封面居中
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: (editable && !_uploading && !_saving) ? _pickCover : null,
                child: Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider, width: 0.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _pendingCover != null && _pendingCover!.isNotEmpty
                        ? WorkCover(url: _pendingCover!, width: 120, height: 160)
                        : const _CoverPlaceholder(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '选择封面',
                style: TextStyle(fontSize: 13, color: AppColors.text3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // 作品名称卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('作品名称',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                maxLength: _titleMax,
                enabled: editable,
                decoration: const InputDecoration(
                  hintText: '请输入作品名称',
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 作品简介卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('作品简介',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _summaryCtrl,
                maxLines: 3,
                enabled: editable,
                decoration: const InputDecoration(
                  hintText: '请输入作品简介',
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 设置项列表卡片
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // 目标读者行
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Text('目标读者', style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    _buildChannelBtn('男频', 146, editable, allTags),
                    const SizedBox(width: 12),
                    _buildChannelBtn('女频', 147, editable, allTags),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16),
              // 阅读标签行
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Text('阅读标签', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: tagsAsync.when(
                        loading: () => const Text('加载中…',
                            style: TextStyle(color: AppColors.text3, fontSize: 13)),
                        error: (_, __) => const Text('标签加载失败',
                            style: TextStyle(color: AppColors.text3, fontSize: 13)),
                        data: (tags) {
                          final selectedTags = tags.where((t) => _tagIds.contains(t.tagId)).toList();
                          return GestureDetector(
                            onTap: editable ? () => _openTagPicker(tags) : null,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    selectedTags.isEmpty
                                        ? '请选择阅读标签'
                                        : selectedTags.map((t) => t.tagName).join('、'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        color: selectedTags.isEmpty ? AppColors.text3 : AppColors.text2,
                                        fontSize: 13),
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16),
              // 定价行
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Text('定价', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        enabled: editable,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          hintText: '0 表示免费',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: (editable && !_saving && !_uploading && !_deleting)
                ? _save
                : null,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TextButton.icon(
            onPressed: (_saving || _uploading || _deleting) ? null : _deleteWork,
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除作品'),
          ),
        ),
      ],
    );
  }
}

/// 标签选择触发行：显示已选标签名称，点击弹出多选弹窗。
class _TagSelector extends StatelessWidget {
  const _TagSelector({
    required this.tags,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final List<TagItem> tags;
  final Set<int> selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final names = [
      for (final tag in tags)
        if (selected.contains(tag.tagId)) tag.tagName,
    ];
    final hasSelection = names.isNotEmpty;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasSelection
                  ? names.join('、')
                  : (enabled ? '请选择标签（最多 $_kMaxWorkTags 个）' : '审核中不可修改'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: hasSelection ? AppColors.text1 : AppColors.text3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.keyboard_arrow_down,
              size: 20, color: AppColors.text3),
        ],
      ),
    );
  }
}

/// 标签多选弹窗：全量标签胶囊可多选，主分类 1 + 主题 2 + 角色 2 + 情节 2。
///
/// 内部维护临时集合，点「确定」通过 `Navigator.pop` 返回最终结果。
class _TagPickerResult {
  final Set<int> tagIds;
  final int channelId;
  _TagPickerResult({required this.tagIds, required this.channelId});
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({
    required this.tags,
    required this.initial,
    required this.initialChannelId,
    required this.maxCount,
  });

  final List<TagItem> tags;
  final Set<int> initial;
  final int initialChannelId;
  final int maxCount;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  late final Set<int> _selected;
  bool _overflow = false;
  int _currentDimIndex = 0;
  int _currentChannelId = 146; // 默认男生频道

  // 维度配置
  final List<Map<String, dynamic>> _dimConfigs = [
    {'type': 'hot', 'title': '主分类', 'max': 1, 'required': true},
    {'type': 'theme', 'title': '主题', 'max': 2, 'required': false},
    {'type': 'role', 'title': '角色', 'max': 2, 'required': false},
    {'type': 'plot', 'title': '情节', 'max': 2, 'required': false},
  ];

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
    _currentChannelId = widget.initialChannelId;
  }

  void _toggle(TagItem tag) {
    setState(() {
      if (_selected.contains(tag.tagId)) {
        _selected.remove(tag.tagId);
        _overflow = false;
      } else {
        // 主分类是单选，选新的自动替换旧的
        if (tag.tagType == 'hot') {
          _selected.removeWhere((id) => widget.tags.firstWhere((t) => t.tagId == id).tagType == 'hot');
          _selected.add(tag.tagId);
          _overflow = false;
          return;
        }
        // 其他维度是多选，按数量限制
        final selectedInType = _selected.where((id) => widget.tags.firstWhere((t) => t.tagId == id).tagType == tag.tagType).length;
        final config = _dimConfigs.firstWhere((c) => c['type'] == tag.tagType);
        if (selectedInType >= config['max']) {
          _overflow = true;
        } else {
          _selected.add(tag.tagId);
          _overflow = false;
        }
      }
    });
  }

  bool get _canSubmit {
    final hotSelected = _selected.where((id) => widget.tags.firstWhere((t) => t.tagId == id).tagType == 'hot').length;
    return hotSelected >= 1;
  }

  @override
  Widget build(BuildContext context) {
    final currentDim = _dimConfigs[_currentDimIndex];
    final tagsInDim = widget.tags
        .where((t) =>
            t.tagType == currentDim['type'] &&
            (t.channelId == _currentChannelId || t.channelId == null))
        .toList();
    final selectedInDim = _selected.where((id) => tagsInDim.any((t) => t.tagId == id)).length;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // 顶部标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  const Text('阅读标签',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _canSubmit ? () => Navigator.of(context).pop(_TagPickerResult(tagIds: _selected, channelId: _currentChannelId)) : null,
                    child: Text(
                      '确认',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _canSubmit ? AppColors.primary : AppColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 说明文字
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '主分类必选且只能选一个，主题、角色、情节最多可选两个',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ),
            ),
            if (_overflow)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('该分类已选满',
                      style: TextStyle(fontSize: 12, color: AppColors.warning)),
                ),
              ),
            const Divider(height: 1, color: AppColors.divider),
            // 主体：左侧维度导航 + 右侧标签墙
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧维度导航
                  Container(
                    width: 80,
                    color: AppColors.pageBackground,
                    child: ListView.builder(
                      itemCount: _dimConfigs.length,
                      itemBuilder: (context, index) {
                        final dim = _dimConfigs[index];
                        final isSelected = index == _currentDimIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _currentDimIndex = index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            color: isSelected ? AppColors.card : Colors.transparent,
                            child: Column(
                              children: [
                                Text(
                                  dim['title'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected ? AppColors.primary : AppColors.text2,
                                  ),
                                ),
                                if (dim['required'])
                                  const Text('*', style: TextStyle(fontSize: 12, color: AppColors.warning)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // 右侧标签墙
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('* ${currentDim['title']}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text1)),
                              const Spacer(),
                              Text('$selectedInDim/${currentDim['max']}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final tag in tagsInDim)
                                SizedBox(
                                  width: (MediaQuery.of(context).size.width - 80 - 32 - 20) / 3,
                                  child: _TagChip(
                                    label: tag.tagName,
                                    selected: _selected.contains(tag.tagId),
                                    onTap: () => _toggle(tag),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// 可选中标签胶囊（样式对齐分类页胶囊，增加选中态）。
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withOpacity(0.12)
          : AppColors.fill,
      borderRadius: BorderRadius.circular(AppRadius.rSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.rSmall),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              color: selected ? AppColors.primary : AppColors.text2,
            ),
          ),
        ),
      ),
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
