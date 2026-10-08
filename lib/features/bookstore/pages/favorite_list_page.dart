import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';
import '../widgets/bookstore_widgets.dart';

/// 我的收藏列表（B 模块，接口 2.7.11）。
///
/// 受登录守卫保护（见 [ProtectedRoutes]）。只展示服务端判定的上架未删除作品，
/// 按收藏时间倒序；取消收藏后原地刷新，归属由服务端身份决定。
class FavoriteListPage extends ConsumerStatefulWidget {
  const FavoriteListPage({super.key});

  @override
  ConsumerState<FavoriteListPage> createState() => _FavoriteListPageState();
}

class _FavoriteListPageState extends ConsumerState<FavoriteListPage> {
  static const int _pageSize = 10;

  late final PagedListController<BookItem> _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = PagedListController<BookItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) => ref
          .read(contentRepositoryProvider)
          .pageFavorites(pageNum: pageNum, pageSize: pageSize),
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

  Future<void> _cancel(BookItem work) async {
    try {
      await ref.read(contentRepositoryProvider).removeFavorite(work.workId);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    // 收藏态随列表一并失效，避免详情页回显旧的「已收藏」。
    ref.invalidate(favoriteStatusProvider(work.workId));
    _controller.load(refresh: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已取消收藏')));
  }

  @override
  Widget build(BuildContext context) {
    return UserCenterScaffold(
      title: '我的收藏',
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
      return const EmptyView(message: '还没有收藏作品', icon: Icons.star_outline);
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
            trailing: IconButton(
              onPressed: () => _cancel(work),
              icon: const Icon(Icons.star, size: 20, color: AppColors.warning),
              tooltip: '取消收藏',
            ),
          );
        },
      ),
    );
  }
}