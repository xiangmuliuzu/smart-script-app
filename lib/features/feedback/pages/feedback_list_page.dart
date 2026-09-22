import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/paged_list_controller.dart';
import '../../user_center/widgets/user_center_widgets.dart';

/// 意见反馈列表（规格 §8.7，契约 §1.6）。
///
/// 展示自己的反馈与处理状态、管理员回复入口；用户只能看到自己的反馈。
class FeedbackListPage extends ConsumerStatefulWidget {
  const FeedbackListPage({super.key});

  @override
  ConsumerState<FeedbackListPage> createState() => _FeedbackListPageState();
}

class _FeedbackListPageState extends ConsumerState<FeedbackListPage> {
  late final PagedListController<FeedbackItem> _controller;
  final _scrollController = ScrollController();
  FeedbackStatus? _filter;

  @override
  void initState() {
    super.initState();
    _controller = PagedListController<FeedbackItem>(
      fetchPage: (pageNum, pageSize) => ref.read(feedbackRepositoryProvider).list(
            status: _filter?.code,
            pageNum: pageNum,
            pageSize: pageSize,
          ),
    );
    _controller.addListener(() => setState(() {}));
    _controller.load();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _controller.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openCreate() async {
    final created = await context.push<bool>(RoutePath.feedbackCreate);
    if (created == true && mounted) {
      await _controller.load(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('意见反馈'),
        actions: [
          TextButton(onPressed: _openCreate, child: const Text('新建')),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Filter(
                    label: '全部',
                    selected: _filter == null,
                    onTap: () => _apply(null),
                  ),
                  for (final status in FeedbackStatus.values)
                    _Filter(
                      label: status.label,
                      selected: _filter == status,
                      onTap: () => _apply(status),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  void _apply(FeedbackStatus? status) {
    if (_filter == status) return;
    setState(() => _filter = status);
    _controller.load(refresh: true);
  }

  Widget _buildList() {
    if (_controller.loading) return const LoadingView(message: '加载中');
    if (_controller.error != null) {
      return ErrorView(message: _controller.error!, onRetry: () => _controller.load(refresh: true));
    }
    if (_controller.isEmpty) {
      return const EmptyView(message: '还没有提交过反馈', icon: Icons.feedback_outlined);
    }
    return RefreshIndicator(
      onRefresh: () => _controller.load(refresh: true),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _controller.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = _controller.items[index];
          return _FeedbackTile(
            item: item,
            onTap: () async {
              await context.push('${RoutePath.feedbackDetail}?id=${item.feedbackId}');
              if (!mounted) return;
              await _controller.load(refresh: true);
            },
          );
        },
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({required this.label, required this.selected, required this.onTap});

  final String label;
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
            border: Border.all(color: selected ? AppColors.primary : Colors.transparent),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? AppColors.primary : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({required this.item, required this.onTap});

  final FeedbackItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: AppColors.card,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserStatusChip(text: item.categoryLabel, color: AppColors.primary),
                const SizedBox(width: 8),
                UserStatusChip(text: item.status.label, color: _statusColor(item.status)),
                const Spacer(),
                if (item.submittedAt != null)
                  Text(
                    item.submittedAt!,
                    style: const TextStyle(fontSize: 11, color: AppColors.text3),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppColors.text1, height: 1.5),
            ),
            if (item.reply != null && item.reply!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '官方回复：${item.reply}',
                  style: const TextStyle(fontSize: 13, color: AppColors.text2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(FeedbackStatus status) {
    switch (status) {
      case FeedbackStatus.submitted:
        return AppColors.text3;
      case FeedbackStatus.processing:
        return AppColors.warning;
      case FeedbackStatus.replied:
        return AppColors.success;
      case FeedbackStatus.closed:
        return AppColors.text3;
    }
  }
}
