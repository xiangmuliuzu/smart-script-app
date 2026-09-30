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
/// 公开页，游客可浏览。支持排序与标签筛选，分页采用触底追加；
/// 分类与关键词由进入本页时固定（来自分类入口或搜索结果），页内不再切换。
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
  int? _tagId;

  @override
  void initState() {
    super.initState();
    _tagId = widget.tagId;
    _controller = PagedListController<BookItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) =>
          ref.read(contentRepositoryProvider).pageWorks(
                categoryId: widget.categoryId,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(widget.title ?? '作品列表')),
      body: Column(
        children: [
          _buildSortBar(),
          _buildTagBar(),
          Expanded(child: _buildList()),
        ],
      ),
    );
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

  /// 标签筛选项：标签为空（或加载失败）时整行隐藏，不阻塞列表。
  Widget _buildTagBar() {
    final tags = ref.watch(tagsProvider).valueOrNull ?? const <TagItem>[];
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