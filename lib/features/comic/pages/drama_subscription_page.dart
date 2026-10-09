import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../data/drama_models.dart';
import '../data/drama_providers.dart';
import '../widgets/drama_widgets.dart';

/// 我的追更（B 模块，接口文档 2.8.14；取消追更 2.8.13）。
///
/// 受登录守卫保护（[RoutePath.dramaSubscriptions]）：归属由服务端身份决定；
/// 取消追更为幂等操作，成功后刷新列表。
class DramaSubscriptionPage extends ConsumerStatefulWidget {
  const DramaSubscriptionPage({super.key});

  @override
  ConsumerState<DramaSubscriptionPage> createState() => _DramaSubscriptionPageState();
}

class _DramaSubscriptionPageState extends ConsumerState<DramaSubscriptionPage> {
  static const int _pageSize = 10;

  late final PagedListController<SubscriptionItem> _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = PagedListController<SubscriptionItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) => ref
          .read(dramaRepositoryProvider)
          .pageSubscriptions(pageNum: pageNum, pageSize: pageSize),
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

  Future<void> _cancel(SubscriptionItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消追更'),
        content: Text('确定取消追更「${item.title.isEmpty ? '该作品' : item.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('取消追更'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(dramaRepositoryProvider).unsubscribe(item.workId);
      messenger.showSnackBar(const SnackBar(content: Text('已取消追更')));
      _controller.load(refresh: true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : '操作失败，请稍后重试'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('我的追更')),
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
      return const EmptyView(message: '暂无追更作品', icon: Icons.bookmark_border);
    }
    return RefreshIndicator(
      onRefresh: () => _controller.load(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _controller.items.length) {
            return LoadMoreFooter<SubscriptionItem>(controller: _controller);
          }
          final item = _controller.items[index];
          return SubscriptionTile(
            item: item,
            onOpen: () => context.push(RoutePath.workDetailUrl(item.workId)),
            onCancel: () => _cancel(item),
          );
        },
      ),
    );
  }
}