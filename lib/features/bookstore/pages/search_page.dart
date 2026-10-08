import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';
import '../widgets/bookstore_widgets.dart';

/// 搜索页（B 模块：接口 2.7.1 关键词搜索 / 2.7.4 历史列表 / 2.7.5 删单条 / 2.7.6 清空）。
///
/// 公开页：游客可输入关键词搜索并浏览结果（走公开的作品列表接口）。
/// 搜索历史需 App Token，故未登录时整块隐藏且不写入历史，避免必然的 401 往返。
/// 结果分页与作品列表页一致（[PagedListController] + 触底追加）。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.keyword});

  /// 进入时预填的关键词（来自外部跳转）；非空则直接搜索。
  final String? keyword;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  static const int _pageSize = 10;

  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final PagedListController<BookItem> _controller;

  /// 已提交的关键词；null 表示尚未搜索，此时展示搜索历史。
  String? _keyword;

  bool get _submitted => _keyword != null && _keyword!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // fetchPage 每次读当前 _keyword：关键词变化由页面调用 load(refresh: true) 重取。
    _controller = PagedListController<BookItem>(
      pageSize: _pageSize,
      fetchPage: (pageNum, pageSize) => ref
          .read(contentRepositoryProvider)
          .pageWorks(keyword: _keyword, pageNum: pageNum, pageSize: pageSize),
    );
    _controller.addListener(_onControllerChanged);
    _scrollController.addListener(_onScroll);

    final initial = widget.keyword?.trim() ?? '';
    if (initial.isNotEmpty) {
      _textController.text = initial;
      _keyword = initial;
      _controller.load();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
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

  /// 提交搜索：空关键词不发起请求（后端会把关键词当过滤条件，空串即无效条件）。
  void _submit() {
    final keyword = _textController.text.trim();
    if (keyword.isEmpty) {
      _showToast('请输入搜索关键词');
      return;
    }
    _focusNode.unfocus();
    setState(() => _keyword = keyword);
    _controller.load(refresh: true);
    _recordHistory(keyword);
  }

  /// 复用历史关键词搜索。
  void _searchKeyword(String keyword) {
    _textController.text = keyword;
    _submit();
  }

  void _onCancel() {
    if (_textController.text.isEmpty && !_submitted) {
      context.pop();
      return;
    }
    _textController.clear();
    setState(() => _keyword = null);
  }

  /// 记录搜索历史（接口 2.7.4 的补充写入接口）：仅登录用户，失败不影响搜索主流程。
  Future<void> _recordHistory(String keyword) async {
    if (!AuthGuard.isLoggedIn(ref)) return;
    try {
      await ref.read(contentRepositoryProvider).recordSearchHistory(keyword);
      ref.invalidate(searchHistoryProvider);
    } catch (_) {
      // 记录历史属于附属动作，失败时静默，不打断本次搜索。
    }
  }

  Future<void> _removeHistory(SearchHistoryItem item) async {
    try {
      await ref.read(contentRepositoryProvider).removeSearchHistory(item.id);
      ref.invalidate(searchHistoryProvider);
    } catch (error) {
      _showToast(error is ApiException ? error.message : '删除失败，请稍后重试');
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text('确定清空全部搜索历史吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(contentRepositoryProvider).clearSearchHistory();
      ref.invalidate(searchHistoryProvider);
    } catch (error) {
      _showToast(error is ApiException ? error.message : '清空失败，请稍后重试');
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 0,
        title: _buildSearchField(),
        actions: [
          TextButton(onPressed: _onCancel, child: const Text('取消')),
          const SizedBox(width: 4),
        ],
      ),
      body: _submitted ? _buildResults() : _buildHistory(),
    );
  }

  /// AppBar 内嵌搜索框：进入自动聚焦，回车即搜索。
  Widget _buildSearchField() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.text3),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 14, color: AppColors.text1),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索作品名称、作者、标签',
                hintStyle: TextStyle(fontSize: 14, color: AppColors.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 未提交关键词时的初始态：仅登录用户展示搜索历史，游客不展示、不请求。
  Widget _buildHistory() {
    if (!AuthGuard.isLoggedIn(ref)) {
      return const EmptyView(message: '输入关键词开始搜索', icon: Icons.search);
    }
    return ref.watch(searchHistoryProvider).when(
          // 历史加载态不占位：字段出现即说明本次已登录，避免闪烁。
          loading: () => const SizedBox.shrink(),
          // 历史拉取失败不阻塞搜索主流程，静默降级为无历史。
          error: (_, __) => const EmptyView(message: '输入关键词开始搜索', icon: Icons.search),
          data: (items) {
            if (items.isEmpty) {
              return const EmptyView(message: '暂无搜索历史', icon: Icons.history);
            }
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
                  child: Row(
                    children: [
                      const Text(
                        '搜索历史',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _clearHistory,
                        child: const Text('清空', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in items)
                        _HistoryChip(
                          keyword: item.keyword,
                          onTap: () => _searchKeyword(item.keyword),
                          onDelete: () => _removeHistory(item),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
  }

  Widget _buildResults() {
    if (_controller.loading) return const LoadingView(message: '搜索中');
    if (_controller.error != null) {
      return ErrorView(
        message: _controller.error!,
        onRetry: () => _controller.load(refresh: true),
      );
    }
    if (_controller.isEmpty) {
      return EmptyView(message: '未找到与「$_keyword」相关的作品', icon: Icons.search_off_outlined);
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

/// 历史关键词胶囊：点击回填并搜索，右侧 × 删除单条。
class _HistoryChip extends StatelessWidget {
  const _HistoryChip({
    required this.keyword,
    required this.onTap,
    required this.onDelete,
  });

  final String keyword;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                keyword,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.text2),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14, color: AppColors.text3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}