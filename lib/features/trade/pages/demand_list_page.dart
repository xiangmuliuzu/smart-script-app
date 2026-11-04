import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
/// 结构：AppBar（透明贴合 + 排序/筛选）→ Hero 渐变横幅 → 分类 chips（带数量角标）→
/// 搜索框（防抖）→ 卡片列表（触底加载更多）。广场仅展示可接取的任务（open+已托管），
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
                color: active ? AppColors.primary : AppColors.text1,
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
      _budgetMinFen != null || _budgetMaxFen != null || _episodesMin != null;

  /// 生效中的筛选条件数（供提示条与图标徽章）。
  int get _filterCount => [
        _budgetMinFen != null,
        _budgetMaxFen != null,
        _episodesMin != null,
      ].where((e) => e).length;

  void _clearFilters() {
    setState(() {
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
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('筛选',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text1)),
            const SizedBox(height: 12),
            const Text('预算区间（元）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)),
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)),
            const SizedBox(height: 8),
            _numField(_episodesCtrl, '如 10'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(false),
                    child: const Text('清空'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(true),
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (applied == null) return; // 点击遮罩关闭，不改
    setState(() {
      if (applied) {
        final minYuan = int.tryParse(_budgetMinCtrl.text.trim());
        final maxYuan = int.tryParse(_budgetMaxCtrl.text.trim());
        _budgetMinFen = minYuan == null ? null : minYuan * 100;
        _budgetMaxFen = maxYuan == null ? null : maxYuan * 100;
        _episodesMin = int.tryParse(_episodesCtrl.text.trim());
      } else {
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
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.text1,
        title: const Text(
          '任务广场',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined, size: 22),
            tooltip: '我的任务',
            onPressed: () => AuthGuard.pushProtected(
              context,
              ref,
              target: RoutePath.demandMyTasks,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.swap_vert, size: 22),
            tooltip: '排序',
            onSelected: _onSortSelected,
            itemBuilder: (_) => _sortMenuItems(),
          ),
          IconButton(
            icon: Icon(
              Icons.tune,
              size: 22,
              color: _filterActive ? AppColors.primary : AppColors.text1,
            ),
            tooltip: '筛选',
            onPressed: _openFilterSheet,
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
            SliverToBoxAdapter(
              child: DemandGenreChipRow(
                selectedGenreId: _selectedGenreId,
                onSelected: (v) {
                  setState(() => _selectedGenreId = v);
                  _applyFilters();
                },
                counts: stats?.genreCounts,
                totalCount: stats?.openCount,
              ),
            ),
            SliverToBoxAdapter(child: _buildSearchField()),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
            // 筛选激活提示条：避免仅靠图标变色不易察觉
            if (_filterActive) SliverToBoxAdapter(child: _buildFilterBanner()),
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
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 0.8),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('已启用 $_filterCount 项筛选',
              style: const TextStyle(fontSize: 12, color: AppColors.text2)),
          const Spacer(),
          GestureDetector(
            onTap: _clearFilters,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text('清除',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.search, size: 18, color: AppColors.text3),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13, color: AppColors.text1),
                decoration: const InputDecoration(
                  hintText: '搜索任务标题 / 编号',
                  hintStyle: TextStyle(fontSize: 13, color: AppColors.placeholder),
                  isDense: true,
                  border: InputBorder.none,
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
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Icon(Icons.close_rounded, size: 16, color: AppColors.text3),
                ),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
          child: ErrorView(
            message: '加载失败：${_pager.error}',
            onRetry: _pager.reset,
          ),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyView(message: _emptyHint()),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('没有更多了',
              style: TextStyle(fontSize: 12, color: AppColors.text3)),
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  String _emptyHint() {
    if (_keyword != null) return '没有匹配的任务，试试换个关键词';
    if (_filterActive) return '当前筛选条件下暂无任务';
    if (_selectedGenreId != null) return '该分类下暂无任务';
    return '暂无任务';
  }
}
