import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/native_file_picker.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../../create/data/author_work_models.dart';
import '../../create/data/author_work_providers.dart';
import '../data/promotion_models.dart';
import '../data/promotion_providers.dart';
import '../widgets/promotion_widgets.dart';

/// 申请推广四步向导：选择作品 → 选资源位 → 选时段 → 确认提交。
///
/// 每一步独立一屏、底部固定主操作，提交前不再折叠长表单，
/// 与 `design/promotion-mockup.html` 的 App 流程一致。
class PromotionCreatePage extends ConsumerStatefulWidget {
  const PromotionCreatePage({super.key});

  @override
  ConsumerState<PromotionCreatePage> createState() =>
      _PromotionCreatePageState();
}

class _PromotionCreatePageState extends ConsumerState<PromotionCreatePage> {
  static const List<_SlotTypeOption> _slotTypes = [
    _SlotTypeOption('banner', '轮播图'),
    _SlotTypeOption('search', '搜索页'),
    _SlotTypeOption('hot', '首页热门精选'),
  ];
  static const List<int> _dayOptions = [7, 15, 30];
  static const List<String> _stepTitles = ['选择作品', '选资源位', '选时段', '确认'];
  static const int _startDateRange = 7;

  int _step = 0;
  int? _workId;
  String _slotType = 'hot';
  int? _slotNo;
  int _days = 7;
  bool _submitting = false;
  String _keyword = '';
  String _materialUrl = '';
  String _materialName = '';
  bool _uploadingMaterial = false;
  late DateTime _startDate;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _slotTypeLabel =>
      _slotTypes.firstWhere((option) => option.value == _slotType).label;

  @override
  Widget build(BuildContext context) {
    final worksAsync = ref.watch(myWorksProvider('all'));
    final slotsAsync = ref.watch(promotionSlotsProvider(_slotType));
    final works = worksAsync.valueOrNull ?? const <AuthorWorkItem>[];
    final selectedWork = _findWork(works);
    final slot = slotsAsync.valueOrNull?.slotByNo(_slotNo);
    final pricePerDay = slot?.pricePerDay ?? 0;
    final total = pricePerDay * _days;

    return PopScope(
      canPop: _step == 0 && !_submitting,
      onPopInvoked: (didPop) {
        if (didPop || _submitting) return;
        if (_step > 0) setState(() => _step -= 1);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: _handleBack,
          ),
          title: Text(_step == 3 ? '确认申请' : '申请推广'),
          actions: [
            if (_step == 0)
              TextButton(
                onPressed: () => showPromotionRulesSheet(context),
                child: const Text(
                  '规则',
                  style: TextStyle(fontSize: 13, color: AppColors.text2),
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            _StepProgress(current: _step, titles: _stepTitles),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                children: [
                  if (_step == 0) _buildWorkStep(worksAsync),
                  if (_step == 1) _buildSlotStep(slotsAsync),
                  if (_step == 2) _buildPeriodStep(slot, pricePerDay, total),
                  if (_step == 3)
                    _buildConfirmStep(selectedWork, slot, pricePerDay, total),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(slot, pricePerDay, total),
      ),
    );
  }

  // ===================== 第 1 步：选择作品 =====================

  Widget _buildWorkStep(AsyncValue<List<AuthorWorkItem>> worksAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchField(),
        const SizedBox(height: 14),
        const _SectionTitle('可申请推广的作品（仅本人已上架）'),
        const SizedBox(height: 8),
        worksAsync.when(
          loading: () => const _InlineLoading(),
          error: (error, _) => _InlineError(
            message: error is ApiException ? error.message : '加载作品失败',
            onRetry: () => ref.invalidate(myWorksProvider),
          ),
          data: (works) {
            final visible = _keyword.isEmpty
                ? works
                : works.where((work) => work.title.contains(_keyword)).toList();
            if (visible.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '暂无可推广的作品，请先在作品设置中上架后再申请推广。',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              );
            }
            return Column(
              children: [
                for (final work in visible) _buildWorkRow(work),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        const _TipBox(
          text: '作品需处于「已上架」且审核通过状态；同一作品同一时段只能占一个坑位。',
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 16, color: AppColors.text3),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _keyword = value.trim()),
              style: const TextStyle(fontSize: 12.5, color: AppColors.text1),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '搜索我的作品',
                hintStyle: TextStyle(fontSize: 12.5, color: AppColors.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkRow(AuthorWorkItem work) {
    final published = work.status == 'published' &&
        (work.shelfStatus.isEmpty || work.shelfStatus == 'on_shelf');
    final selected = _workId == work.workId;

    return Opacity(
      opacity: published ? 1 : 0.55,
      child: GestureDetector(
        onTap: published
            ? () => setState(() => _workId = work.workId)
            : () => showAppToast(context, '未上架作品不可申请推广'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF7FAFE) : AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _buildRadio(selected),
              const SizedBox(width: 10),
              WorkCover(
                url: work.cover ?? '',
                title: work.title,
                width: 38,
                height: 50,
                radius: 6,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.title.isEmpty ? '未命名作品' : work.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${work.workType ?? '未分类'} · ${work.wordCount} 字',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.text3,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.fill,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  published ? '已上架' : work.statusLabel,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.text3,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadio(bool selected) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.primary : const Color(0xFFC9CFD8),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
          : null,
    );
  }

  // ===================== 第 2 步：选择资源位 =====================

  Widget _buildSlotStep(AsyncValue<PromotionSlotPage> slotsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSegmented(),
        const SizedBox(height: 14),
        if (_slotType == 'banner') ...[
          const _SectionTitle('轮播素材（16:9，审核通过后到点自动展示）'),
          const SizedBox(height: 8),
          _buildMaterialCard(),
          const SizedBox(height: 14),
        ],
        const _SectionTitle('选择坑位（同一时段冲突会在提交时提示）'),
        const SizedBox(height: 8),
        slotsAsync.when(
          loading: () => const _InlineLoading(),
          error: (error, _) => _InlineError(
            message: error is ApiException ? error.message : '加载位次失败',
            onRetry: () => ref.invalidate(promotionSlotsProvider),
          ),
          data: (page) {
            if (page.slots.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '该资源位暂未配置推广位次，请选择其他资源位。',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              );
            }
            return Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: page.slots.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    mainAxisExtent: 84,
                  ),
                  itemBuilder: (context, index) {
                    final slot = page.slots[index];
                    return PromotionSlotCard(
                      slot: slot,
                      selected: _slotNo == slot.slotNo,
                      onTap: () => _selectSlot(slot),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _TipBox(text: _slotTip()),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSegmented() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF0F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final option in _slotTypes)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _slotType = option.value;
                  _slotNo = null;
                }),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _slotType == option.value
                        ? AppColors.card
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _slotType == option.value
                        ? const [
                            BoxShadow(
                              color: Color(0x141F2329),
                              offset: Offset(0, 2),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _slotType == option.value
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: _slotType == option.value
                          ? AppColors.text1
                          : AppColors.text2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMaterialCard() {
    return GestureDetector(
      onTap: _uploadingMaterial ? null : _pickMaterial,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: _materialUrl.isEmpty
            ? Container(
                height: 96,
                alignment: Alignment.center,
                child: _uploadingMaterial
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 26,
                            color: AppColors.text3,
                          ),
                          SizedBox(height: 6),
                          Text(
                            '上传 16:9 轮播素材',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.text3,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '建议 1920×1080，JPG/PNG',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: AppColors.text3,
                            ),
                          ),
                        ],
                      ),
              )
            : Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      AppConfig.resolveAssetUrl(_materialUrl),
                      fit: BoxFit.cover,
                      cacheWidth: 1080,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.fill,
                        alignment: Alignment.center,
                        child: const Text(
                          '素材预览失败',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.text3,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '更换',
                        style: TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
                  if (_uploadingMaterial)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _pickMaterial() async {
    try {
      final picked = await NativeFilePicker.pickFile(
        filenamePrefix: 'banner',
        type: FileType.image,
      );
      if (picked == null) return;
      if (!mounted) return;
      if (picked.size > 5 * 1024 * 1024) {
        showAppToast(context, '素材不能超过 5MB，请压缩后重试');
        return;
      }
      setState(() => _uploadingMaterial = true);
      final url = await ref
          .read(promotionRepositoryProvider)
          .uploadBannerMaterial(bytes: picked.bytes, fileName: picked.filename);
      if (!mounted) return;
      setState(() {
        _materialUrl = url;
        _materialName = picked.filename;
        _uploadingMaterial = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingMaterial = false);
      showAppToast(
        context,
        error is NativeFileException
            ? error.message
            : error is ApiException
                ? error.message
                : '素材上传失败，请稍后重试',
      );
    }
  }

  void _selectSlot(PromotionSlotItem slot) {
    if (!slot.selectable) {
      showAppToast(
        context,
        slot.enabled ? '该位次${slot.stateLabel}，暂不可预约' : '该位次已停用',
      );
      return;
    }
    setState(() => _slotNo = slot.slotNo);
  }

  String _slotTip() {
    switch (_slotType) {
      case 'search':
        return '搜索页付费作品优先展示，其余按顺序插入自然搜索结果之间。';
      case 'banner':
        return '轮播位按序位依次展示；付费素材生效时会覆盖同序位的运营素材。';
      default:
        return '第 1–6 位直接展示在首页「热门精选」；第 7 位起需点击「更多」后可见，价格更低。';
    }
  }

  // ===================== 第 3 步：选择时段 =====================

  Widget _buildPeriodStep(
    PromotionSlotItem? slot,
    double pricePerDay,
    double total,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('开始日期'),
        const SizedBox(height: 8),
        SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _startDateRange,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _buildDateChip(index),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('投放周期'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final days in _dayOptions)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: _buildDurationChip(days, pricePerDay),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const _SectionTitle('费用明细'),
        const SizedBox(height: 8),
        _Surface(
          child: Column(
            children: [
              _feeRow(
                slot == null ? '资源位' : '$_slotTypeLabel · 第${slot.slotNo}位',
                slot == null
                    ? '—'
                    : '¥${formatPromotionMoney(pricePerDay)} / 天',
              ),
              _feeRow('投放时长', '$_days 天'),
              _feeRow('投放时段', _periodText()),
              const Padding(
                padding: EdgeInsets.only(top: 11),
                child: Divider(height: 1, color: AppColors.divider),
              ),
              Row(
                children: [
                  const Text(
                    '合计',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text1,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '¥${formatPromotionMoney(total)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _TipBox(
          text: '审核通过后 48 小时内完成支付，逾期坑位自动释放；投放开始后不支持退款。',
          accent: true,
        ),
      ],
    );
  }

  Widget _buildDateChip(int index) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    final date = base.add(Duration(days: index));
    final selected = _startDate.year == date.year &&
        _startDate.month == date.month &&
        _startDate.day == date.day;

    return GestureDetector(
      onTap: () => setState(
        () => _startDate = DateTime(date.year, date.month, date.day),
      ),
      child: Container(
        width: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.text1,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${date.month}月',
              style: TextStyle(
                fontSize: 9,
                color: selected ? Colors.white70 : AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(int days, double pricePerDay) {
    final selected = _days == days;
    return GestureDetector(
      onTap: () => setState(() => _days = days),
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF7FAFE) : AppColors.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$days 天',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text1,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pricePerDay <= 0
                  ? '待选位次'
                  : '¥${formatPromotionMoney(pricePerDay * days)}',
              style: const TextStyle(fontSize: 9, color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.text2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: AppColors.text1),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== 第 4 步：确认提交 =====================

  Widget _buildConfirmStep(
    AuthorWorkItem? work,
    PromotionSlotItem? slot,
    double pricePerDay,
    double total,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Surface(
          child: Column(
            children: [
              Row(
                children: [
                  WorkCover(
                    url: work?.cover ?? '',
                    title: work?.title ?? '',
                    width: 44,
                    height: 58,
                    radius: 7,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          work == null || work.title.isEmpty
                              ? '未选择作品'
                              : work.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${work?.workType ?? '未分类'} · ${work?.wordCount ?? 0} 字',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 2),
                child: Divider(height: 1, color: AppColors.divider),
              ),
              _sumRow(
                '资源位',
                slot == null ? '未选择' : '$_slotTypeLabel · 第${slot.slotNo}位',
              ),
              if (_slotType == 'banner') ...[
                _sumRow(
                  '轮播素材',
                  _materialUrl.isEmpty
                      ? '未上传'
                      : '已上传${_materialName.isEmpty ? '' : ' · $_materialName'}',
                ),
                if (_materialUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          AppConfig.resolveAssetUrl(_materialUrl),
                          fit: BoxFit.cover,
                          cacheWidth: 1080,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.fill,
                            alignment: Alignment.center,
                            child: const Text(
                              '素材预览失败',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.text3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              _sumRow('展示位置', _displayPosition()),
              _sumRow('投放时段', _periodText()),
              _sumRow('投放周期', '$_days 天'),
              _sumRow(
                '单价',
                pricePerDay <= 0
                    ? '—'
                    : '¥${formatPromotionMoney(pricePerDay)} / 天',
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 2),
                child: Divider(height: 1, color: AppColors.divider),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '应付金额',
                    style: TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                  const Spacer(),
                  Text(
                    '¥${formatPromotionMoney(total)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _TipBox(
          text: '提交后进入人工审核；审核通过会锁定该坑位 48 小时，请在有效期内完成支付宝支付，逾期自动释放且不可恢复。',
          accent: true,
        ),
      ],
    );
  }

  Widget _sumRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.text3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayPosition() {
    switch (_slotType) {
      case 'search':
        return '搜索结果页推荐位';
      case 'banner':
        return '首页顶部轮播';
      default:
        return (_slotNo ?? 0) <= 6 ? '首页「热门精选」直接可见' : '首页「更多」页内可见';
    }
  }

  // ===================== 底部操作与提交 =====================

  Widget _buildBottomBar(
    PromotionSlotItem? slot,
    double pricePerDay,
    double total,
  ) {
    final label = switch (_step) {
      0 => '下一步 · 选资源位',
      1 => '下一步 · 选时段',
      2 => '下一步 · 确认信息',
      _ => '提交申请',
    };

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            offset: Offset(0, -2),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step == 1 && slot != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      '已选：第 ${slot.slotNo} 位 · '
                      '¥${formatPromotionMoney(pricePerDay)}/天',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '预计 ¥${formatPromotionMoney(total)} 起',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: _submitting
                    ? null
                    : _step == 3
                        ? _submit
                        : _next,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _step == 3 ? AppColors.accent : AppColors.primary,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleBack() {
    if (_submitting) return;
    if (_step > 0) {
      setState(() => _step -= 1);
      return;
    }
    context.pop();
  }

  void _next() {
    switch (_step) {
      case 0:
        if (_workId == null) {
          showAppToast(context, '请选择推广作品');
          return;
        }
        setState(() => _step = 1);
      case 1:
        final slot = ref
            .read(promotionSlotsProvider(_slotType))
            .valueOrNull
            ?.slotByNo(_slotNo);
        if (slot == null || !slot.selectable) {
          showAppToast(context, '请选择可预约的推广位次');
          return;
        }
        if (_slotType == 'banner' && _materialUrl.isEmpty) {
          showAppToast(context, '请先上传轮播素材');
          return;
        }
        setState(() => _step = 2);
      case 2:
        setState(() => _step = 3);
    }
  }

  AuthorWorkItem? _findWork(List<AuthorWorkItem> works) {
    for (final work in works) {
      if (work.workId == _workId) return work;
    }
    return null;
  }

  String _periodText() {
    final end = _startDate.add(Duration(days: _days - 1));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(_startDate.month)}-${two(_startDate.day)} 至 '
        '${two(end.month)}-${two(end.day)}';
  }

  Future<void> _submit() async {
    if (_workId == null) {
      showAppToast(context, '请选择推广作品');
      return;
    }
    final slot = ref
        .read(promotionSlotsProvider(_slotType))
        .valueOrNull
        ?.slotByNo(_slotNo);
    if (slot == null || !slot.selectable) {
      showAppToast(context, '请选择可预约的推广位次');
      return;
    }

    setState(() => _submitting = true);
    try {
      final application = await ref.read(promotionRepositoryProvider).apply(
            workId: _workId!,
            slotType: _slotType,
            slotNo: slot.slotNo,
            days: _days,
            startTime: _startDate,
            materialUrl: _slotType == 'banner' ? _materialUrl : null,
          );
      ref.invalidate(myPromotionsProvider);
      ref.invalidate(promotionSlotsProvider(_slotType));
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(context, '推广申请已提交，等待审核');
      context
          .pushReplacement(RoutePath.promotionDetailUrl(application.applyId));
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(
        context,
        error is ApiException ? error.message : '提交失败，请稍后重试',
      );
    }
  }
}

class _SlotTypeOption {
  const _SlotTypeOption(this.value, this.label);

  final String value;
  final String label;
}

/// 四段进度条：已完成段填充主色，未完成段留灰。
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current, required this.titles});

  final int current;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          for (var index = 0; index < titles.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 3,
                    decoration: BoxDecoration(
                      color: index <= current
                          ? AppColors.primary
                          : const Color(0xFFE5E6EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${index + 1} ${titles[index]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          index <= current ? FontWeight.w600 : FontWeight.w400,
                      color: index <= current
                          ? AppColors.text1
                          : AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.text2,
      ),
    );
  }
}

/// 白底圆角信息面板。
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            offset: Offset(0, 4),
            blurRadius: 16,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 规则提示条：默认主色，accent 用于费用/提交提醒。
class _TipBox extends StatelessWidget {
  const _TipBox({required this.text, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.accent : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent ? AppColors.accentSoft : AppColors.primaryTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: accent ? AppColors.accent : AppColors.text1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: const TextStyle(fontSize: 12, color: AppColors.text2),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('重试', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
