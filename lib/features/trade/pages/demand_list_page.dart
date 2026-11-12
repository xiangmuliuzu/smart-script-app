import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/demand_genre.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/paged_data.dart';
import '../data/demand_pager.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';
import '../widgets/demand_genre_chip_row.dart';
import '../widgets/demand_hero_banner.dart';
import '../widgets/demand_task_card.dart';

/// 任务广场列表页（需求接单制 · 门户风格）。
///
/// 结构：AppBar（透明贴合 + 我的任务）→ Hero 页头与统计卡 →
/// 工具条（搜索 + 排序 + 筛选）→ 结果头 → 卡片列表（触底加载更多）。
/// 题材、预算、集数统一收在筛选弹层，顶栏不放常驻 chips，避免占高与滑动找项。
/// 广场仅展示可接取的任务（open+已托管），
/// 自己发布的未托管/已接单等其他状态任务只在"我的任务"查看。
class DemandListPage extends ConsumerStatefulWidget {
  const DemandListPage({super.key});

  @override
  ConsumerState<DemandListPage> createState() => _DemandListPageState();
}

class _DemandListPageState extends ConsumerState<DemandListPage> {
  static const int _pageSize = 20;

  final _searchController = TextEditingController();
  final _budgetMinCtrl = TextEditingController();
  final _budgetMaxCtrl = TextEditingController();
  final _episodesCtrl = TextEditingController();

  late final DemandPager _pager;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  int? _selectedGenreId;
  String? _keyword;
  String _sortBy = 'created'; // created / budget / deadline
  String _order = 'desc'; // asc / desc
  int? _budgetMinFen;
  int? _budgetMaxFen;
  int? _episodesMin;

  @override
  void initState() {
    super.initState();
    _pager = DemandPager(_loadPage, pageSize: _pageSize)
      ..addListener(_onPagerChanged);
    _scrollCtrl.addListener(_onScroll);
    _pager.reset();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pager.removeListener(_onPagerChanged);
    _pager.dispose();
    _scrollCtrl.dispose();
    _searchController.dispose();
    _budgetMinCtrl.dispose();
    _budgetMaxCtrl.dispose();
    _episodesCtrl.dispose();
    super.dispose();
  }

  void _onPagerChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 240) {
      _pager.loadMore();
    }
  }

  /// 供分页器调用：以当前筛选态拉取第 [pageNum] 页。
  Future<PagedData<DemandTask>> _loadPage(int pageNum) {
    return ref.read(demandRepositoryProvider).pageDemands(
          genreId: _selectedGenreId,
          keyword: _keyword,
          sortBy: _sortBy,
          order: _order,
          budgetMinFen: _budgetMinFen,
          budgetMaxFen: _budgetMaxFen,
          episodesMin: _episodesMin,
          pageNum: pageNum,
          pageSize: _pageSize,
        );
  }

  void _applyFilters() => _pager.reset();

  // ==================== 搜索（防抖 + 清空即还原） ====================

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final trimmed = v.trim();
      setState(() => _keyword = trimmed.isEmpty ? null : trimmed);
      _applyFilters();
    });
  }

  void _onSearchSubmitted(String v) {
    _debounce?.cancel();
    final trimmed = v.trim();
    setState(() => _keyword = trimmed.isEmpty ? null : trimmed);
    _applyFilters();
  }

  void _clearKeyword() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _keyword = null);
    _applyFilters();
  }

  // ==================== 排序 / 筛选 ====================

  void _onSortSelected(String v) {
    setState(() {
      if (v == _sortBy) {
        // 同一排序项再次点击：切换升/降方向
        _order = _order == 'desc' ? 'asc' : 'desc';
      } else {
        _sortBy = v;
        _order = v == 'deadline' ? 'asc' : 'desc'; // 即将截止=近在前，其余大/新在前
      }
    });
    _applyFilters();
  }

  /// 排序菜单：当前项显勾选与方向箭头；标签随激活/方向动态变化（再点即反向）。
  List<PopupMenuEntry<String>> _sortMenuItems() {
    PopupMenuItem<String> item(String v, String label) {
      final active = _sortBy == v;
      return PopupMenuItem<String>(
        value: v,
        child: Row(
          children: [
            Icon(
              active ? Icons.check : Icons.unfold_more,
              size: 16,
              color: active ? AppColors.primary : AppColors.text3,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: TextStyle(
                fontSize: 14,
                color: AppColors.text1,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              )),
            ),
            if (active)
              Icon(_order == 'desc' ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 14, color: AppColors.primary),
          ],
        ),
      );
    }

    return [
      item('created', _sortBy == 'created' ? (_order == 'desc' ? '最新发布在前' : '最早发布在前') : '按发布时间'),
      item('budget', _sortBy == 'budget' ? (_order == 'desc' ? '预算高 → 低' : '预算低 → 高') : '按预算'),
      item('deadline', _sortBy == 'deadline' ? (_order == 'asc' ? '截止近 → 远' : '截止远 → 近') : '按截止日期'),
    ];
  }

  bool get _filterActive =>
      _selectedGenreId != null ||
      _budgetMinFen != null ||
      _budgetMaxFen != null ||
      _episodesMin != null;

  /// 生效中的筛选条件数（供提示条与图标徽章）。
  int get _filterCount => [
        _selectedGenreId != null,
        _budgetMinFen != null,
        _budgetMaxFen != null,
        _episodesMin != null,
      ].where((e) => e).length;

  void _clearFilters() {
    setState(() {
      _selectedGenreId = null;
      _budgetMinFen = null;
      _budgetMaxFen = null;
      _episodesMin = null;
    });
    _applyFilters();
  }

  Future<void> _openFilterSheet() async {
    _budgetMinCtrl.text = _budgetMinFen == null ? '' : '${_budgetMinFen! ~/ 100}';
    _budgetMaxCtrl.text = _budgetMaxFen == null ? '' : '${_budgetMaxFen! ~/ 100}';
    _episodesCtrl.text = _episodesMin?.toString() ?? '';
    final stats = ref.read(demandStatsProvider).valueOrNull;
    // 题材在弹层内是暂存态，点“应用”才生效
    var sheetGenreId = _selectedGenreId;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          // 题材多页 + 键盘弹出时靠滚动兜底，避免 Column 溢出
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('筛选',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text1)),
                const SizedBox(height: 12),
                // 题材：横排一行 4 个，满 5 行左滑翻页，不显页数
                const Text('题材',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 8),
                DemandGenreChipRow(
                  selectedGenreId: sheetGenreId,
                  onSelected: (v) => setSheetState(() => sheetGenreId = v),
                  counts: stats?.genreCounts,
                  totalCount: stats?.openCount,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 14),
                const Text('预算区间（元）',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _numField(_budgetMinCtrl, '最低预算')),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('—', style: TextStyle(color: AppColors.text3)),
                    ),
                    Expanded(child: _numField(_budgetMaxCtrl, '最高预算')),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('最少集数',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 8),
                _numField(_episodesCtrl, '如 10'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('清空'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('应用'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == null) return; // 点击遮罩关闭，不改
    setState(() {
      if (applied) {
        _selectedGenreId = sheetGenreId;
        final minYuan = int.tryParse(_budgetMinCtrl.text.trim());
        final maxYuan = int.tryParse(_budgetMaxCtrl.text.trim());
        _budgetMinFen = minYuan == null ? null : minYuan * 100;
        _budgetMaxFen = maxYuan == null ? null : maxYuan * 100;
        _episodesMin = int.tryParse(_episodesCtrl.text.trim());
      } else {
        _selectedGenreId = null;
        _budgetMinFen = null;
        _budgetMaxFen = null;
        _episodesMin = null;
      }
    });
    _applyFilters();
  }

  Widget _numField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 14, color: AppColors.text1),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.placeholder),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
      ),
    );
  }

  // ==================== build ====================

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(demandStatsProvider);
    final stats = statsAsync.valueOrNull;

    return Scaffold(
      // 透明底透出 AppPageBackground 的全局冰蓝渐变，与首页/我的页同背景
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.text1,
        title: const Text(
          '任务广场',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          // 图标 + 文案合并成一个轻量胶囊按钮：淡底淡字，字号收敛，避免抢过居中标题
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Material(
                color: Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => AuthGuard.pushProtected(
                    context,
                    ref,
                    target: RoutePath.demandMyTasks,
                  ),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.16)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_outlined,
                            size: 14, color: AppColors.text3),
                        SizedBox(width: 5),
                        Text(
                          '我的任务',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(demandStatsProvider);
          await _pager.reset();
        },
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 发布/托管流程 pop 返回后刷新列表与统计
            SliverToBoxAdapter(
              child: DemandHeroBanner(
                stats: stats,
                onPublish: () async {
                  await context.push(RoutePath.demandPost);
                  if (!mounted) return;
                  ref.invalidate(demandStatsProvider);
                  _pager.reset();
                },
              ),
            ),
            // 题材已收进筛选弹层，这里只留统计卡到工具条的区间留白
            const SliverToBoxAdapter(child: SizedBox(height: 14)),
            SliverToBoxAdapter(child: _buildToolbar()),
            // 筛选激活提示条：避免仅靠图标变色不易察觉
            if (_filterActive) SliverToBoxAdapter(child: _buildFilterBanner()),
            SliverToBoxAdapter(child: _buildResultHead()),
            ..._buildListSlivers(),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// 筛选激活提示条：显示生效条件数，一键清除回落到纯浏览态。
  Widget _buildFilterBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 14, color: AppColors.primary),
          const SizedBox(width: 7),
          Text('已启用 $_filterCount 项筛选',
              style: const TextStyle(fontSize: 11.5, color: AppColors.text2)),
          const Spacer(),
          GestureDetector(
            onTap: _clearFilters,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text('清除',
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.text1, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索 + 排序 + 筛选：一条工具带，替代原先散在 AppBar 的三个图标。
  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Row(
        children: [
          Expanded(child: _buildSearchField()),
          const SizedBox(width: 8),
          _SortButton(
            label: _sortLabel,
            ascending: _order == 'asc',
            items: _sortMenuItems(),
            onSelected: _onSortSelected,
          ),
          const SizedBox(width: 8),
          _FilterButton(count: _filterCount, onTap: _openFilterSheet),
        ],
      ),
    );
  }

  /// 排序按钮短文案：菜单里已有完整说明，这里只留维度名。
  String get _sortLabel => switch (_sortBy) {
        'budget' => '预算',
        'deadline' => '截止',
        _ => '最新',
      };

  Widget _buildSearchField() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, size: 17, color: AppColors.text3),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12.5, color: AppColors.text1),
              decoration: const InputDecoration(
                hintText: '搜索任务标题 / 编号',
                hintStyle: TextStyle(fontSize: 12.5, color: AppColors.placeholder),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
            ),
          ),
          if (_keyword != null)
            GestureDetector(
              onTap: _clearKeyword,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                child: Icon(Icons.close_rounded, size: 15, color: AppColors.text3),
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// 结果头：与首页区块标题同款「主色竖条 + 标题」，右侧给总数。
  Widget _buildResultHead() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _selectedGenreId == null
                ? '征集中的任务'
                : '征集中的任务 · ${DemandGenre.labelOf(_selectedGenreId!)}',
            style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.text1),
          ),
          const Spacer(),
          Text(
            _pager.loaded ? '共 ${_pager.total} 个' : '',
            style: const TextStyle(fontSize: 11.5, color: AppColors.text3),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildListSlivers() {
    final items = _pager.items;
    final myId = ref.watch(authControllerProvider).user?.userId;

    // 首屏加载：骨架屏占位（保持卡片布局形状，减少跳动）
    if (_pager.loading && items.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          sliver: SliverList.separated(
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, __) => const DemandCardSkeleton(),
          ),
        ),
      ];
    }
    if (_pager.error != null && items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 44),
            child: ErrorView(
              message: '加载失败：${_pager.error}',
              onRetry: _pager.reset,
            ),
          ),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 52),
            child: EmptyView(message: _emptyHint(), icon: Icons.search_off_rounded),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          // 详情 pop 返回后重拉第一页并刷新统计（接单/关闭/编辑后不留陈旧卡片）
          itemBuilder: (context, i) => DemandTaskCard(
            task: items[i],
            isMine: myId != null && items[i].clientId == myId,
            onTap: () async {
              final id = items[i].demandId;
              if (id == null) return;
              await context.push(RoutePath.demandDetailUrl(id));
              if (!mounted) return;
              ref.invalidate(demandStatsProvider);
              _pager.reset();
            },
          ),
        ),
      ),
      SliverToBoxAdapter(child: _buildFooter()),
    ];
  }

  Widget _buildFooter() {
    if (_pager.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    // 不满一页（首屏即全部）时不显"没有更多了"，避免无信息量文案
    if (!_pager.hasMore && _pager.items.length >= _pager.pageSize) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 18, height: 0.6, color: AppColors.divider),
            const SizedBox(width: 8),
            const Text('没有更多了',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
            const SizedBox(width: 8),
            Container(width: 18, height: 0.6, color: AppColors.divider),
          ],
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  String _emptyHint() {
    if (_keyword != null) return '没有匹配的任务，试试换个关键词';
    if (_filterActive) return '当前筛选条件下暂无任务';
    return '暂无任务';
  }
}

/// 排序入口：白底胶囊，显示当前维度与升降方向。
class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.label,
    required this.ascending,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final bool ascending;
  final List<PopupMenuEntry<String>> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '排序',
      onSelected: onSelected,
      itemBuilder: (_) => items,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.divider, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert, size: 15, color: AppColors.text2),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
            const SizedBox(width: 2),
            Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 11,
              color: AppColors.text3,
            ),
          ],
        ),
      ),
    );
  }
}

/// 筛选入口：圆形按钮，生效条件数用橙色角标提示。
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.divider,
                  width: 0.8,
                ),
              ),
              child: Icon(
                Icons.tune,
                size: 18,
                color: active ? Colors.white : AppColors.text2,
              ),
            ),
            if (active)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 15,
                  height: 15,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 1.2),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w700,
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
}
