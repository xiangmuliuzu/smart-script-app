import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/paged_data.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';
import '../data/content_repository.dart';
import '../widgets/bookstore_widgets.dart';

/// 我的书架（B 模块，接口 2.7.12 书架管理）。
///
/// 受登录守卫保护（见 [ProtectedRoutes]）。列表为真实分页数据（只含服务端判定的
/// 上架未删除作品，按加入书架时间倒序）；移出书架为物理删除，归属由服务端身份决定。
///
/// 身份摘要块（identity / downloadable / realNameRequired）随列表接口一并下发，
/// 首屏即具备，用于展示实名准入等身份信息（与角色授权分开判断）。
class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  static const int _pageSize = 10;

  late final PagedListController<BookItem> _controller;
  final ScrollController _scrollController = ScrollController();

  /// 最近一次列表响应中的身份摘要块（每页都下发，缓存最新一份供卡片展示）。
  ShelfPayload? _payload;

  @override
  void initState() {
    super.initState();
    _controller = PagedListController<BookItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) async {
        final payload = await ref
            .read(contentRepositoryProvider)
            .shelf(pageNum: pageNum, pageSize: pageSize);
        _payload = payload;
        return PagedData<BookItem>(total: payload.total, list: payload.list);
      },
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

  Future<void> _remove(BookItem work) async {
    try {
      await ref.read(contentRepositoryProvider).removeShelf(work.workId);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    // 书架态与个人中心预览区块一并失效，避免详情页/个人中心回显旧的「已在书架」。
    ref.invalidate(shelfStatusProvider(work.workId));
    ref.invalidate(shelfProvider);
    _controller.load(refresh: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已移出书架')));
  }

  @override
  Widget build(BuildContext context) {
    return UserCenterScaffold(
      title: '我的书架',
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
    final payload = _payload;
    // 身份卡片与列表同源；载荷未就绪时不渲染卡片，避免出现空壳。
    final headerCount = payload == null ? 0 : 1;
    final showEmpty = _controller.items.isEmpty;
    final listCount = showEmpty
        ? 1
        : _controller.items.length + (_controller.hasMore ? 1 : 0);
    return RefreshIndicator(
      onRefresh: () => _controller.load(refresh: true),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: headerCount + listCount,
        separatorBuilder: (_, __) => const Divider(height: 0.5, color: AppColors.divider),
        itemBuilder: (context, index) {
          if (headerCount == 1 && index == 0) {
            return _IdentityCard(payload: payload!);
          }
          final itemIndex = index - headerCount;
          if (showEmpty) return const _EmptyShelf();
          if (itemIndex >= _controller.items.length) {
            return LoadMoreFooter<BookItem>(controller: _controller);
          }
          final work = _controller.items[itemIndex];
          return WorkListTile(
            work: work,
            onTap: () => context.push(RoutePath.workDetailUrl(work.workId)),
            trailing: IconButton(
              onPressed: () => _remove(work),
              icon: const Icon(Icons.bookmark_remove_outlined,
                  size: 20, color: AppColors.text3),
              tooltip: '移出书架',
            ),
          );
        },
      ),
    );
  }
}

/// 书架空态：放在列表内部（需与身份卡片同屏），故不用整屏 [EmptyView]。
class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.menu_book_outlined, size: 40, color: AppColors.text3),
          SizedBox(height: 10),
          Text('书架暂无作品，去书城添加吧',
              style: TextStyle(fontSize: 13, color: AppColors.text3)),
        ],
      ),
    );
  }
}

/// 身份摘要卡片：直接展示后端下发的身份字段，用于验证跨模块身份联通。
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.payload});

  final ShelfPayload payload;

  @override
  Widget build(BuildContext context) {
    final identity = payload.identity;
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                '身份摘要（由服务端下发）',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _line('登录状态', identity.authenticated ? '已登录' : '游客'),
          _line('用户 ID', identity.userId?.toString() ?? '（无，游客不伪造 ID）'),
          _line('账号类型', identity.accountType ?? '-'),
          _line('实名状态', identity.realNameStatus),
          // 业务准入：实名通过才可下载素材，与角色授权独立判断
          _line('素材下载',
              payload.downloadable ? '已开放（实名通过）' : '需先完成实名认证'),
          _line('作者能力', identity.authorCapability ? '已开通' : '未开通'),
          _line('角色', identity.roleCodes.isEmpty ? '无' : identity.roleCodes.join('、')),
          _line('权限数', '${identity.permissionCodes.length}'),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13, color: AppColors.text1)),
            ),
          ],
        ),
      );
}