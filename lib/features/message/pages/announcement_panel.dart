import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/announcement_repository.dart';
import '../data/announcement_providers.dart';

class AnnouncementPanel extends ConsumerStatefulWidget {
  const AnnouncementPanel({super.key});
  @override
  ConsumerState<AnnouncementPanel> createState() => _AnnouncementPanelState();
}

class _AnnouncementPanelState extends ConsumerState<AnnouncementPanel> {
  late final PagedListController<AnnouncementItem> _controller;
  final _scroll = ScrollController();
  bool _markingAll = false;
  @override
  void initState() {
    super.initState();
    _controller = PagedListController(
        fetchPage: (page, size) => ref
            .read(announcementRepositoryProvider)
            .list(pageNum: page, pageSize: size));
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _controller.load();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 200) _controller.loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(announcementUnreadProvider);
    await _controller.load(refresh: true);
  }

  Future<void> _readAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await ref.read(announcementRepositoryProvider).markAllRead();
      if (!mounted) return;
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('标记失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _open(AnnouncementItem item) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AnnouncementDetailPage(noticeId: item.noticeId)));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(announcementUnreadProvider);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
                child: Text(
                    count.hasError
                        ? '公告未读统计暂不可用'
                        : '未读公告 ${count.valueOrNull ?? '—'}',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.text3))),
            IconButton(
                onPressed: _refresh,
                tooltip: '刷新公告',
                icon: const Icon(Icons.refresh)),
            TextButton(
                onPressed: _markingAll ? null : _readAll,
                child: Text(_markingAll ? '处理中' : '全部已读')),
          ])),
      Expanded(child: _list()),
    ]);
  }

  Widget _list() {
    if (_controller.loading) return const LoadingView(message: '加载中');
    if (_controller.error != null) {
      return ErrorView(message: _controller.error!, onRetry: _refresh);
    }
    if (_controller.isEmpty) {
      return const EmptyView(message: '暂无平台公告', icon: Icons.campaign_outlined);
    }
    return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index >= _controller.items.length) {
              return LoadMoreFooter<AnnouncementItem>(controller: _controller);
            }
            final item = _controller.items[index];
            return ListTile(
              leading: Icon(
                  item.read ? Icons.campaign_outlined : Icons.campaign,
                  color: item.read ? AppColors.text3 : AppColors.primary),
              title: Text(item.title,
                  style: TextStyle(
                      fontWeight:
                          item.read ? FontWeight.normal : FontWeight.w600)),
              subtitle: Text('${item.typeLabel} · ${item.createdAt ?? ''}'),
              trailing: Text(item.read ? '已读' : '未读',
                  style: const TextStyle(fontSize: 12)),
              onTap: () => _open(item),
            );
          },
        ));
  }
}

class AnnouncementDetailPage extends ConsumerStatefulWidget {
  const AnnouncementDetailPage({super.key, required this.noticeId});
  final int noticeId;
  @override
  ConsumerState<AnnouncementDetailPage> createState() =>
      _AnnouncementDetailPageState();
}

class _AnnouncementDetailPageState
    extends ConsumerState<AnnouncementDetailPage> {
  AnnouncementItem? _notice;
  String? _error;
  bool _loading = true, _marking = false, _readError = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _readError = false;
    });
    try {
      final notice = await ref
          .read(announcementRepositoryProvider)
          .detail(widget.noticeId);
      if (!mounted) return;
      setState(() {
        _notice = notice;
        _loading = false;
      });
      if (!notice.read) await _markRead();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is ApiException ? e.message : '公告加载失败';
        });
      }
    }
  }

  Future<void> _markRead() async {
    if (_marking) return;
    setState(() {
      _marking = true;
      _readError = false;
    });
    try {
      await ref.read(announcementRepositoryProvider).markRead(widget.noticeId);
      if (mounted) ref.invalidate(announcementUnreadProvider);
    } catch (_) {
      if (mounted) setState(() => _readError = true);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      UserCenterScaffold(title: '公告详情', body: _body());
  Widget _body() {
    if (_loading) return const LoadingView(message: '加载中');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final notice = _notice;
    if (notice == null) return const EmptyView(message: '公告不存在');
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserStatusChip(text: notice.typeLabel, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(notice.title,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(notice.createdAt ?? '',
              style: const TextStyle(fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 20),
          SelectableText(notice.content ?? '',
              style: const TextStyle(fontSize: 15, height: 1.7)),
          if (_readError) ...[
            const SizedBox(height: 16),
            TextButton(
                onPressed: _marking ? null : _markRead,
                child: const Text('已读状态更新失败，点击重试'))
          ],
        ]));
  }
}
