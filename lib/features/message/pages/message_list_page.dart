import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/services/realtime_socket.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 消息中心（规格 §8.6，契约 §1.5）。
///
/// 支持分页、按类型筛选、未读数、单条已读与批量已读；已读操作幂等。
class MessageListPage extends ConsumerStatefulWidget {
  const MessageListPage({super.key});

  @override
  ConsumerState<MessageListPage> createState() => _MessageListPageState();
}

class _MessageListPageState extends ConsumerState<MessageListPage>
    with WidgetsBindingObserver {
  late final PagedListController<MessageItem> _controller;
  final _scrollController = ScrollController();

  /// 当前筛选类型；null 表示全部。
  MessageType? _filter;
  Timer? _timer;
  StreamSubscription<RealtimeEvent>? _realtime;
  bool _foreground = true;

  /// 兜底轮询频率：长连接可用时拉长，事件帧负责即时刷新。
  static const Duration _pollActive = Duration(seconds: 5);
  static const Duration _pollIdle = Duration(seconds: 60);
  Duration _cadence = _pollActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = PagedListController<MessageItem>(
      fetchPage: (pageNum, pageSize) =>
          ref.read(messageRepositoryProvider).list(
                type: _filter?.code,
                pageNum: pageNum,
                pageSize: pageSize,
                includeAnnouncements: true,
              ),
    );
    _controller.addListener(() => setState(() {}));
    _controller.load();
    _cadence = ref.read(realtimeSocketProvider).isConnected ? _pollIdle : _pollActive;
    _timer = Timer.periodic(_cadence, (_) => _poll());
    _realtime = ref.read(realtimeSocketProvider).events.listen(_onRealtime);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _controller.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _realtime?.cancel();
    _realtime = null;
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _poll();
  }

  void _poll() {
    if (!mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    ref.invalidate(unreadCountProvider);
    _controller.refreshSilently();
  }

  /// 实时帧驱动刷新；链路连通状态变化时调整兜底轮询频率。
  void _onRealtime(RealtimeEvent event) {
    switch (event.type) {
      case 'connected':
        _applyCadence(idle: true);
        break;
      case 'disconnected':
        _applyCadence(idle: false);
        break;
      case 'reconnect':
        // 断线期间可能积压了消息，立刻补拉而不是干等下一轮
        _applyCadence(idle: ref.read(realtimeSocketProvider).isConnected);
        _poll();
        break;
      case 'notification':
      case 'chat':
        _poll();
        break;
    }
  }

  void _applyCadence({required bool idle}) {
    final target = idle ? _pollIdle : _pollActive;
    if (_cadence == target || _timer == null) return;
    _cadence = target;
    _timer!.cancel();
    _timer = Timer.periodic(target, (_) => _poll());
  }

  Future<void> _refresh() async {
    ref.invalidate(unreadCountProvider);
    await _controller.load(refresh: true);
  }

  Future<void> _markAllRead() async {
    try {
      await ref
          .read(messageRepositoryProvider)
          .markAllRead(includeAnnouncements: true);
      if (!mounted) return;
      ref.invalidate(unreadCountProvider);
      await _controller.load(refresh: true);
      _toast('已全部标记为已读');
    } catch (_) {
      _toast('操作失败，请稍后重试');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return UserCenterScaffold(
      title: '消息中心',
      actions: [
        IconButton(
            onPressed: _refresh,
            tooltip: '刷新通知',
            icon: const Icon(Icons.refresh)),
        TextButton(
            onPressed: _controller.isEmpty ? null : _markAllRead,
            child: const Text('全部已读')),
      ],
      body: Column(children: [_buildFilters(), Expanded(child: _buildList())]),
    );
  }

  Widget _buildFilters() {
    final unread = ref.watch(unreadCountProvider).valueOrNull;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChip(
              label: '全部',
              count: unread?.total ?? 0,
              selected: _filter == null,
              onTap: () => _applyFilter(null),
            ),
            for (final type in MessageType.values)
              _FilterChip(
                label: type.label,
                count: unread?.byType[type.code] ?? 0,
                selected: _filter == type,
                onTap: () => _applyFilter(type),
              ),
          ],
        ),
      ),
    );
  }

  void _applyFilter(MessageType? type) {
    if (_filter == type) return;
    setState(() => _filter = type);
    _controller.load(refresh: true);
  }

  Widget _buildList() {
    if (_controller.loading) return const LoadingView(message: '加载中');
    if (_controller.error != null) {
      return ErrorView(
          message: _controller.error!,
          onRetry: () => _controller.load(refresh: true));
    }
    if (_controller.isEmpty) {
      return const EmptyView(message: '暂无消息', icon: Icons.notifications_none);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
        separatorBuilder: (_, __) =>
            const Divider(height: 0.5, color: AppColors.divider),
        itemBuilder: (context, index) {
          if (index >= _controller.items.length) {
            return LoadMoreFooter<MessageItem>(controller: _controller);
          }
          final item = _controller.items[index];
          return _MessageTile(
            key: ValueKey('${item.source}:${item.messageId}'),
            item: item,
            onTap: () async {
              await context.push(
                  '${RoutePath.messageDetail}?id=${item.messageId}&source=${item.source}');
              // 详情页可能标记已读：返回后刷新列表与未读数
              if (!mounted) return;
              ref.invalidate(unreadCountProvider);
              await _controller.load(refresh: true);
            },
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryTint : AppColors.fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? AppColors.primary : Colors.transparent),
          ),
          child: Text(
            count > 0 ? '$label $count' : label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? AppColors.text1 : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({super.key, required this.item, required this.onTap});

  final MessageItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserStatusChip(
                          text: item.typeLabel, color: AppColors.primary),
                      const SizedBox(width: 8),
                      if (!item.read)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                      // 交易通知可直达业务页：列表先行提示
                      if (item.type == 'TRANSACTION' &&
                          (item.businessId ?? '').isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.open_in_new,
                              size: 14, color: AppColors.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: item.read ? FontWeight.w400 : FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 13, color: AppColors.text3),
                    ),
                  ],
                  if (item.createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.createdAt!,
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.text3),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}
