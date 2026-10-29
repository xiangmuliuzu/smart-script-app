import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../shared/widgets/common_views.dart';
import '../user_center/widgets/paged_list_controller.dart';
import 'data/drama_models.dart';
import 'data/drama_providers.dart';
import 'widgets/drama_widgets.dart';

/// 漫剧（B 模块，接口文档 2.8.1 短剧信息流）。
///
/// 抖音式竖向视频流：一屏一个视频，上下滑动切换，切到哪一页哪一页自动播放。
/// 公开页，游客可浏览；滑到接近列表尾部时自动追加分页。
/// 「播放历史」「我的追更」是受保护入口，由 [AuthGuard.pushProtected] 统一拦截。
class ComicPage extends ConsumerStatefulWidget {
  const ComicPage({super.key});

  @override
  ConsumerState<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends ConsumerState<ComicPage> {
  static const int _pageSize = 10;

  late final PagedListController<DramaFeedItem> _controller;
  final PageController _pageController = PageController();
  int _currentIndex = 0;

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
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// 滑到倒数第二页时预取下一页，保证继续下滑不中断。
  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    if (index >= _controller.items.length - 2) {
      _controller.loadMore();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('视频'),
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
      return const EmptyView(message: '暂无视频内容', icon: Icons.smart_display_outlined);
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController,
      onPageChanged: _onPageChanged,
      itemCount: _controller.items.length,
      itemBuilder: (context, index) {
        final item = _controller.items[index];
        return DramaVideoPane(
          key: ValueKey<int>(item.dramaId),
          item: item,
          active: index == _currentIndex,
          onOpenDetail: () => context.push(RoutePath.dramaDetailUrl(item.dramaId)),
          onOpenRelated: () => context.push(RoutePath.dramaRelatedWorkUrl(item.dramaId)),
        );
      },
    );
  }
}