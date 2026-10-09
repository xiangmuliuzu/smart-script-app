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
/// 公开页，游客可浏览。支持排序、分类与标签筛选，分页采用触底追加。
/// 分类与标签可叠加（如「都市 + 重生」）：切换分类时标签条按其
/// 联动刷新（只显示该分类下的标签）；关键词由搜索入口固定，页内不改。
class WorkListPage extends ConsumerStatefulWidget {
  const WorkListPage({
    super.key,
    this.title,
    this.categoryId,
    this.tagId,
    this.keyword,
  });

  /// 页面标题（分类名等），仅展示用。
  final String? title;
  final int? categoryId;
  final int? tagId;
  final String? keyword;

  @override
  ConsumerState<WorkListPage> createState() => _WorkListPageState();
}

class _WorkListPageState extends ConsumerState<WorkListPage> {
  static const int _pageSize = 10;

  late final PagedListController<BookItem> _controller;
  final ScrollController _scrollController = ScrollController();

  /// null 表示不传 sort，由后端回落 `latest`。
  String? _sort;

  /// 分类/标签筛选：进入时由路由参数给初值，页内可随时叠加切换。
  int? _categoryId;
  int? _tagId;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
    _tagId = widget.tagId;
    _controller = PagedListController<BookItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) =>
          ref.read(contentRepositoryProvider).pageWorks(
                categoryId: _categoryId,
                tagId: _tagId,
                keyword: widget.keyword,
                sort: _sort,
                pageNum: pageNum,
                pageSize: pageSize,
              ),
    );
    _controller.addListener(_onControllerChanged);
    _controller.load();
    _scrollController.addListener(_onScroll);
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

  /// 切换分类：标签选项随之联动刷新（只显示新分类下的标签）。
  /// 若当前标签不属于新分类，则一并清空，避免「无匹配标签却仍在过滤」的静默空结果。
  Future<void> _applyCategory(int? categoryId) async {
    if (_categoryId == categoryId) return;
    setState(() => _categoryId = categoryId);
    if (_tagId != null) {
      List<TagItem> tags;
      try {
        tags = await ref.read(tagsProvider(categoryId).future);
      } catch (_) {
        tags = const <TagItem>[];
      }
      if (!mounted) return;
      if (!tags.any((tag) => tag.tagId == _tagId)) {
        setState(() => _tagId = null);
      }
    }
    _controller.load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <CategoryItem>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(_pageTitle(categories))),
      body: Column(
        children: [
          _buildSortBar(),
          _buildCategoryBar(categories),
          _buildTagBar(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  /// 标题跟随页内选中的分类：选中分类时显示分类名；未选（全部分类）时，
  /// 若进入页面时本就带分类（后被清空）则回落通用标题，否则保留传入标题
  /// （搜索关键词等入口）。
  String _pageTitle(List<CategoryItem> categories) {
    if (_categoryId == null) {
      return widget.categoryId == null ? (widget.title ?? '作品列表') : '作品列表';
    }
    for (final category in categories) {
      if (category.categoryId == _categoryId) return category.categoryName;
    }
    // 分类列表尚未加载完成时，先用进入页面时的标题兜底。
    return widget.title ?? '作品列表';
  }

  Widget _buildSortBar() {
    return Container(
      color: AppColors.card,
      child: FilterChipBar(
        items: [
          for (final option in WorkSortOption.all)
            FilterChipItem(
              label: option.label,
              selected: option.value == _sort,
              onTap: () => _applySort(option.value),
            ),
        ],
      ),
    );
  }

  /// 分类筛选项：分类为空（或加载失败）时整行隐藏，不阻塞列表。
  Widget _buildCategoryBar(List<CategoryItem> categories) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return Container(
      color: AppColors.card,
      child: FilterChipBar(
        items: [
          FilterChipItem(
            label: '全部分类',
            selected: _categoryId == null,
            onTap: () => _applyCategory(null),
          ),
          for (final category in categories)
            FilterChipItem(
              label: category.categoryName,
              selected: category.categoryId == _categoryId,
              onTap: () => _applyCategory(category.categoryId),
            ),
        ],
      ),
    );
  }

  /// 标签筛选项：随当前分类联动（只显示该分类下的标签）；
  /// 为空（或加载失败）时整行隐藏，不阻塞列表。
  Widget _buildTagBar() {
    final tags = ref.watch(tagsProvider(_categoryId)).valueOrNull ?? const <TagItem>[];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Container(
      color: AppColors.card,
      child: FilterChipBar(
        items: [
          FilterChipItem(
            label: '全部标签',
            selected: _tagId == null,
            onTap: () => _applyTag(null),
          ),
          for (final tag in tags)
            FilterChipItem(
              label: tag.tagName,
              selected: tag.tagId == _tagId,
              onTap: () => _applyTag(tag.tagId),
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_controller.loading) return const LoadingView(message: '加载中');
    if (_controller.error != null) {
      return ErrorView(
        message: _controller.error!,
        onRetry: () => _controller.load(refresh: true),
      );
    }
    if (_controller.isEmpty) {
      return const EmptyView(message: '暂无作品', icon: Icons.menu_book_outlined);
    }
    return RefreshIndicator(
      onRefresh: () => _controller.load(refresh: true),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
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