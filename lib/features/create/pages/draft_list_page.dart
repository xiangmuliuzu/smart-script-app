import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../data/create_models.dart';
import '../data/create_providers.dart';

/// 我的草稿箱（APP 页面13，接口 2.9.5 列表 + 2.9.4 删除）。
///
/// 受登录守卫保护（见 [ProtectedRoutes]）；草稿口径=status='draft' 且本人，
/// 归属由服务端身份决定。点击进入编辑页，删除需二次确认。
class DraftListPage extends ConsumerStatefulWidget {
  const DraftListPage({super.key});

  @override
  ConsumerState<DraftListPage> createState() => _DraftListPageState();
}

class _DraftListPageState extends ConsumerState<DraftListPage> {
  static const int _pageSize = 10;

  late final PagedListController<DraftWorkItem> _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = PagedListController<DraftWorkItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) => ref
          .read(createRepositoryProvider)
          .pageDrafts(pageNum: pageNum, pageSize: pageSize),
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

  Future<void> _delete(DraftWorkItem work) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除草稿'),
        content: Text('确定删除《${work.title.isEmpty ? '未命名作品' : work.title}》吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(createRepositoryProvider).deleteWork(work.workId);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    // 草稿列表由控制器驱动，刷新即可；同时失效缓存的分页 provider。
    ref.invalidate(draftListProvider(1));
    _controller.load(refresh: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
  }

  @override
  Widget build(BuildContext context) {
    return UserCenterScaffold(title: '草稿箱', body: _buildBody());
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
      return const EmptyView(message: '暂无草稿', icon: Icons.edit_note_outlined);
    }
    return RefreshIndicator(
      onRefresh: () => _controller.load(refresh: true),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 0.5, color: AppColors.divider),
        itemBuilder: (context, index) {
          if (index >= _controller.items.length) {
            return LoadMoreFooter<DraftWorkItem>(controller: _controller);
          }
          final work = _controller.items[index];
          return _DraftTile(
            work: work,
            onTap: () => context.push(
              RoutePath.workEditUrl(
                workId: work.workId,
                title: work.title,
                description: work.summary,
                price: work.price,
                genreId: work.genreId,
              ),
            ),
            onDelete: () => _delete(work),
          );
        },
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.work, required this.onTap, required this.onDelete});

  final DraftWorkItem work;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final genre = work.genreName;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorkCover(url: work.cover ?? ''),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.title.isEmpty ? '未命名作品' : work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (genre == null || genre.isEmpty) ? '未分类' : genre,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                  if (work.summary != null && work.summary!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      work.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.text2),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '${work.priceLabel} · ${work.createTime ?? '时间未知'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
              tooltip: '删除草稿',
            ),
          ],
        ),
      ),
    );
  }
}