import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';
import '../widgets/bookstore_widgets.dart';

/// 作品列表（B 模块，接口 2.7.1 作品列表）。
///
/// 公开页，游客可浏览。支持排序与标签筛选，分页采用触底追加。
/// 标签墙体系下作品只按标签归属，不再有分类筛选；关键词由搜索入口固定，页内不改。
class WorkListPage extends ConsumerStatefulWidget {
  const WorkListPage({
    super.key,
    this.title,
    this.tagId,
    this.keyword,
    this.showScope,
  });

  /// 页面标题（标签名等），仅展示用。
  final String? title;
  final int? tagId;
  final String? keyword;

  /// 推荐展示位过滤（如 bookstore=书城推荐）；传入则变为推荐列表页
  final String? showScope;

  @override
  ConsumerState<WorkListPage> createState() => _WorkListPageState();
}

class _WorkListPageState extends ConsumerState<WorkListPage> {
  static const int _pageSize = 10;

  late final PagedListController<BookItem> _controller;
  final ScrollController _scrollController = ScrollController();

  /// null 表示不传 sort，由后端回落 `latest`。
  String? _sort;

  /// 推荐展示位过滤（如 bookstore=书城推荐）；null 表示不过滤。
  String? _showScope;

  /// 标签筛选：进入时由路由参数给初值，页内可随时切换。
  int? _tagId;

  /// 首屏引导只做一次：didChangeDependencies 里读完路由 sort 后再发首屏请求。
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _tagId = widget.tagId;
    _controller = PagedListController<BookItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) =>
          ref.read(contentRepositoryProvider).pageWorks(
                tagId: _tagId,
                keyword: widget.keyword,
                sort: _sort,
                showScope: _showScope,
                pageNum: pageNum,
                pageSize: pageSize,
              ),
    );
    _controller.addListener(_onControllerChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    // 首页「热门作品/最新作品」等入口通过 workListUrl(sort: ...) 带初始排序。
    // app_router 的 builder 未显式透传 sort，这里直接读本路由 uri 的 query；
    // 取值须落在后端 normalizeSort 白名单（WorkSortOption.all.value）内，否则忽略。
    final routeSort = GoRouterState.of(context).uri.queryParameters['sort'];
    if (routeSort != null &&
        WorkSortOption.all.any((option) => option.value == routeSort)) {
      _sort = routeSort;
    }
    // 直接用 widget 传入的 showScope，不依赖路由读取
    if (widget.showScope != null && widget.showScope!.isNotEmpty) {
      _showScope = widget.showScope;
    }
    _controller.load();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _controller.loadMore();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applySort(String? value) {
    if (_sort == value) return;
    setState(() => _sort = value);
    _controller.load(refresh: true);
  }

  void _applyTag(int? tagId) {
    if (_tagId == tagId) return;
    setState(() => _tagId = tagId);
    _controller.load(refresh: true);
  }

  /// 清空标签筛选并重载（仅「带筛选的空态」入口使用；排序与外部关键词不动）。
  void _resetFilters() {
    setState(() => _tagId = null);
    _controller.load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(widget.title ?? '作品列表')),
      body: Column(
        children: [
          _buildSortBar(),
          _buildFilterBar(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildSortBar() {
    // 顶栏透明后不再铺白色通栏，胶囊直接浮在页面渐变背景上。
    return FilterChipBar(
      items: [
        for (final option in WorkSortOption.all)
          FilterChipItem(
            label: option.label,
            selected: option.value == _sort,
            onTap: () => _applySort(option.value),
          ),
      ],
    );
  }

  /// 标签筛选：选项较多时横向滚动难以选全，改用下拉按钮 + 底部弹窗选择。
  /// 标签为空（或加载失败）时下拉隐藏，不阻塞列表。
  Widget _buildFilterBar() {
    final tags = ref.watch(tagsProvider).valueOrNull ?? const <TagItem>[];
    final filters = <FilterDropdownFilter>[
      if (tags.isNotEmpty)
        FilterDropdownFilter(
          label: '标签',
          valueText: _selectedTagName(tags) ?? '全部标签',
          options: [
            FilterDropdownOption(
              label: '全部标签',
              selected: _tagId == null,
              onTap: () => _applyTag(null),
            ),
            for (final tag in tags)
              FilterDropdownOption(
                label: tag.tagName,
                selected: tag.tagId == _tagId,
                onTap: () => _applyTag(tag.tagId),
              ),
          ],
        ),
    ];
    if (filters.isEmpty) return const SizedBox.shrink();
    return FilterDropdownBar(filters: filters);
  }

  /// 当前选中标签名；未选或标签尚未加载完成时返回 null，由调用方回落默认文案。
  String? _selectedTagName(List<TagItem> tags) {
    for (final tag in tags) {
      if (tag.tagId == _tagId) return tag.tagName;
    }
    return null;
  }

  Widget _buildList() {
    // 首屏无数据时整屏展示加载/错误；已有数据时保留列表，下拉刷新由 RefreshIndicator 反馈。
    if (_controller.loading && _controller.isEmpty) {
      return const LoadingView(message: '加载中');
    }
    if (_controller.error != null && _controller.isEmpty) {
      return ErrorView(
        message: _controller.error!,
        onRetry: () => _controller.load(refresh: true),
      );
    }
    if (_controller.isEmpty) {
      // 无筛选条件时保持原空态；带筛选却为空时追加「重置筛选」，引导用户清空条件后重载。
      final hasFilter = _tagId != null;
      if (!hasFilter) {
        return const EmptyView(message: '暂无作品', icon: Icons.menu_book_outlined);
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 56, color: AppColors.text3),
            const SizedBox(height: 12),
            const Text('暂无作品', style: TextStyle(color: AppColors.text3)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _resetFilters,
              child: const Text('重置筛选'),
            ),
          ],
        ),
      );
    }
    // 推荐列表页最多显示 30 本，不显示加载更多
    final isRecommendList = _showScope != null;
    final maxItems = isRecommendList ? 30 : _controller.items.length;
    final itemCount = isRecommendList
        ? maxItems.clamp(0, _controller.items.length)
        : _controller.items.length + (_controller.hasMore ? 1 : 0);
    return RefreshIndicator(
      onRefresh: () => _controller.load(refresh: true),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const Divider(height: 0.5, color: AppColors.divider),
        itemBuilder: (context, index) {
          if (index >= _controller.items.length) {
            return LoadMoreFooter<BookItem>(controller: _controller);
          }
          final work = _controller.items[index];
          return WorkListTile(
            work: work,
            onTap: () => context.push(RoutePath.workDetailUrl(work.workId)),
          );
        },
      ),
    );
  }
}