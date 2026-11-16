import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/demand_pager.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';
import '../../user_center/data/paged_data.dart';
import '../widgets/demand_task_card.dart';

/// 任务广场·我的任务分段：我接取的任务。
///
/// - mine=claimed，展示当前用户作为创作者抢到的全部任务（含各状态）；
/// - 发布方已收归平台运营，普通用户不再有"我发布的"视角。
/// 支持状态筛选 + 触底加载更多（补齐广场只曝光 open 的全状态视图）。
///
/// 本组件只输出正文：外层 AppBar 由宿主提供（tab 根 `TaskSquarePage`、
/// 深链薄壳 [DemandMyTasksPage]）。宿主须保证只在已登录时构建本组件——
/// 游客拉 mine 列表会拿到 401，而 App 的 ApiClient 对 401 一律按会话过期处理。
class DemandMyTasksSection extends ConsumerStatefulWidget {
  const DemandMyTasksSection({super.key});

  @override
  ConsumerState<DemandMyTasksSection> createState() =>
      DemandMyTasksSectionState();
}

class DemandMyTasksSectionState extends ConsumerState<DemandMyTasksSection> {
  /// 交付/接单流程 pop 返回后由宿主触发重拉。
  final _claimedKey = GlobalKey<_MyTaskListState>();

  void reload() => _claimedKey.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    return _MyTaskListTab(key: _claimedKey);
  }
}

/// 「我的任务」独立页（深链兼容）：正文复用 [DemandMyTasksSection]，
/// 与 tab 根的第二个分段共用同一套状态机，避免两份实现漂移。
class DemandMyTasksPage extends ConsumerStatefulWidget {
  const DemandMyTasksPage({super.key});

  @override
  ConsumerState<DemandMyTasksPage> createState() => _DemandMyTasksPageState();
}

class _DemandMyTasksPageState extends ConsumerState<DemandMyTasksPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.text1,
        title: const Text(
          '我的任务',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: const DemandMyTasksSection(),
    );
  }
}

/// 我接取的任务列表（状态筛选 + 分页）。
class _MyTaskListTab extends ConsumerStatefulWidget {
  const _MyTaskListTab({super.key});

  @override
  ConsumerState<_MyTaskListTab> createState() => _MyTaskListState();
}

class _MyTaskListState extends ConsumerState<_MyTaskListTab>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 20;

  late final DemandPager _pager;
  final ScrollController _scrollCtrl = ScrollController();
  String? _status;

  /// 状态筛选顺序（null=全部）。selected 为遗留态，不单列。
  static const List<String?> _statusOptions = [
    null,
    DemandStatus.open,
    DemandStatus.inProgress,
    DemandStatus.completed,
    DemandStatus.failed,
    DemandStatus.closed,
  ];

  @override
  bool get wantKeepAlive => true;

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
    _pager.removeListener(_onPagerChanged);
    _pager.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onPagerChanged() {
    if (mounted) setState(() {});
  }

  /// 供父页在发布/编辑流程返回后触发重拉。
  void reload() => _pager.reset();

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 240) {
      _pager.loadMore();
    }
  }

  Future<PagedData<DemandTask>> _loadPage(int pageNum) {
    return ref.read(demandRepositoryProvider).pageDemands(
          mine: 'claimed',
          status: _status,
          pageNum: pageNum,
          pageSize: _pageSize,
        );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _pager.items;
    return Column(
      children: [
        _buildStatusFilter(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _pager.reset,
            child: _buildList(items),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusFilter() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _statusOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = _statusOptions[i];
          final selected = _status == s;
          return ChoiceChip(
            label: Text(s == null ? '全部' : DemandStatus.label(s)),
            selected: selected,
            labelStyle: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : AppColors.text2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
            selectedColor: AppColors.primary,
            backgroundColor: Colors.white,
            showCheckmark: false,
            shape: const StadiumBorder(),
            onSelected: (_) {
              setState(() => _status = s);
              _pager.reset();
            },
          );
        },
      ),
    );
  }

  Widget _buildList(List<DemandTask> items) {
    if (_pager.loading && items.isEmpty) {
      // 首屏骨架屏：保持卡片布局形状，减少整屏转圈的跳动
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const DemandCardSkeleton(),
      );
    }
    if (_pager.error != null && items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          ErrorView(message: '加载失败：${_pager.error}', onRetry: _pager.reset),
        ],
      );
    }
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyView(message: _emptyHint()),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      itemCount: items.length + 1,
      separatorBuilder: (_, i) => i < items.length - 1 ? const SizedBox(height: 10) : const SizedBox(height: 4),
      itemBuilder: (context, i) {
        if (i == items.length) return _buildFooter();
        // 详情 pop 返回后重拉第一页（接单/交付/关闭/编辑后不留陈旧卡片）
        return DemandTaskCard(
          task: items[i],
          onTap: () async {
            final id = items[i].demandId;
            if (id == null) return;
            await context.push(RoutePath.demandDetailUrl(id));
            if (!mounted) return;
            ref.invalidate(demandStatsProvider);
            _pager.reset();
          },
        );
      },
    );
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
    // 不满一页时不显"没有更多了"，避免无信息量文案
    if (!_pager.hasMore && _pager.items.length >= _pager.pageSize) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('没有更多了', style: TextStyle(fontSize: 12, color: AppColors.text3)),
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  String _emptyHint() {
    if (_status != null) {
      return '该状态下暂无任务（${DemandStatus.label(_status)}）';
    }
    return '还没有接取过任务';
  }
}
