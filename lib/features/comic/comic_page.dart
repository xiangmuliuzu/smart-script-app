import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../shared/widgets/common_views.dart';
import '../user_center/widgets/paged_list_controller.dart';
import '../user_center/widgets/user_center_widgets.dart';
import 'data/drama_models.dart';
import 'data/drama_providers.dart';
import 'widgets/drama_widgets.dart';

/// 漫剧（B 模块，接口文档 2.8.1 短剧信息流）。
///
/// 公开页，游客可浏览。信息流按触底追加分页；
/// 「播放历史」「我的追更」是受保护入口，由 [AuthGuard.pushProtected] 统一拦截。
class ComicPage extends ConsumerStatefulWidget {
  const ComicPage({super.key});

  @override
  ConsumerState<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends ConsumerState<ComicPage> {
  static const int _pageSize = 10;

  late final PagedListController<DramaFeedItem> _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = PagedListController<DramaFeedItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) => ref
          .read(dramaRepositoryProvider)
          .pageFeed(pageNum: pageNum, pageSize: pageSize),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('漫剧'),
        actions: [
          IconButton(
            tooltip: '播放历史',
            onPressed: () => AuthGuard.pushProtected(
              context,
              ref,
              target: RoutePath.dramaHistory,
            ),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: '我的追更',
            onPressed: () => AuthGuard.pushProtected(
              context,
              ref,
              target: RoutePath.dramaSubscriptions,
            ),
            icon: const Icon(Icons.bookmark_border),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_controller.loading) return const LoadingView(message: '加载中');
    if (_controller.error != null) {
      return ErrorView(
        message: _controller.error!,
        onRetry: () => _controller.load(refresh: true),
      );
    }
    if (_controller.isEmpty) {
      return const EmptyView(message: '暂无漫剧内容', icon: Icons.smart_display_outlined);
    }
    return RefreshIndicator(
      onRefresh: () => _controller.load(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _controller.items.length) {
            return LoadMoreFooter<DramaFeedItem>(controller: _controller);
          }
          final item = _controller.items[index];
          return DramaFeedCard(
            item: item,
            onTap: () => context.push(RoutePath.dramaDetailUrl(item.dramaId)),
          );
        },
      ),
    );
  }
}