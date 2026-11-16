import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../data/drama_models.dart';
import '../data/drama_providers.dart';
import '../widgets/drama_widgets.dart';

/// 播放历史（B 模块，接口文档 2.8.6）。
///
/// 受登录守卫保护（[RoutePath.dramaHistory]）：归属由服务端身份决定；
/// 点击某条回到对应剧集播放页继续观看。
class DramaHistoryPage extends ConsumerStatefulWidget {
  const DramaHistoryPage({super.key});

  @override
  ConsumerState<DramaHistoryPage> createState() => _DramaHistoryPageState();
}

class _DramaHistoryPageState extends ConsumerState<DramaHistoryPage> {
  static const int _pageSize = 10;

  late final PagedListController<PlayHistoryItem> _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = PagedListController<PlayHistoryItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) => ref
          .read(dramaRepositoryProvider)
          .pagePlayHistory(pageNum: pageNum, pageSize: pageSize),
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
      appBar: AppBar(title: const Text('播放历史')),
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
      return const EmptyView(message: '暂无播放历史', icon: Icons.history);
    }
    return RefreshIndicator(
      onRefresh: () => _controller.load(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _controller.items.length) {
            return LoadMoreFooter<PlayHistoryItem>(controller: _controller);
          }
          final item = _controller.items[index];
          return PlayHistoryTile(
            item: item,
            onTap: () => context.push(
              RoutePath.dramaPlayUrl(item.workId, episodeId: item.episodeId),
            ),
          );
        },
      ),
    );
  }
}