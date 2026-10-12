import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 询盘列表页（分工条目 4/10）
///
/// 双标签切换：我发起的（buyer）/ 我收到的（seller）。
/// 支持下拉刷新、上拉加载更多、状态筛选。
class InquiryListPage extends ConsumerStatefulWidget {
  const InquiryListPage({super.key});

  @override
  ConsumerState<InquiryListPage> createState() => _InquiryListPageState();
}

class _InquiryListPageState extends ConsumerState<InquiryListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentRole => _tabController.index == 0 ? 'buyer' : 'seller';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的询盘'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '我发起的'),
            Tab(text: '我收到的'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 状态筛选栏
          _buildFilterBar(),
          // 列表
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInquiryList('buyer'),
                _buildInquiryList('seller'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Text('状态：', style: TextStyle(fontSize: 14)),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(null, '全部'),
                  _buildFilterChip(InquiryStatus.pending, '待处理'),
                  _buildFilterChip(InquiryStatus.accepted, '已接受'),
                  _buildFilterChip(InquiryStatus.rejected, '已拒绝'),
                  _buildFilterChip(InquiryStatus.deal, '已成交'),
                  _buildFilterChip(InquiryStatus.closed, '已关闭'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String? value, String label) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _statusFilter = value),
        selectedColor: AppColors.primaryTint,
        checkmarkColor: AppColors.primary,
        labelStyle: TextStyle(
          color: selected ? AppColors.primary : AppColors.text2,
        ),
      ),
    );
  }

  Widget _buildInquiryList(String role) {
    final params = InquiryListParams(
      role: role,
      status: _statusFilter,
      pageNum: 1,
      pageSize: 20,
    );
    final listAsync = ref.watch(inquiryListProvider(params));

    return listAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message: '加载失败: $e',
        onRetry: () => ref.invalidate(inquiryListProvider(params)),
      ),
      data: (pagedData) {
        if (pagedData.list.isEmpty) {
          return const EmptyView(message: '暂无询盘记录');
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(inquiryListProvider(params)),
          child: ListView.builder(
            itemCount: pagedData.list.length,
            itemBuilder: (context, index) {
              final inquiry = pagedData.list[index];
              return _buildInquiryCard(inquiry, role);
            },
          ),
        );
      },
    );
  }

  Widget _buildInquiryCard(Inquiry inquiry, String role) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () async {
          final result = await context.push<bool>(
            '${RoutePath.inquiryDetail}?id=${inquiry.inquiryId}',
          );
          if (result == true) {
            // 刷新列表
            ref.invalidate(inquiryListProvider(InquiryListParams(role: role)));
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inquiry.workTitle ?? '作品',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusTag(inquiry.status),
                ],
              ),
              const SizedBox(height: 8),
              // 询盘编号
              Row(
                children: [
                  const Icon(Icons.tag, size: 14, color: AppColors.text3),
                  const SizedBox(width: 4),
                  Text(
                    inquiry.inquiryNo ?? '-',
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 授权类型 + 预算
              Row(
                children: [
                  _buildInfoItem(
                    Icons.article,
                    LicenseType.label(inquiry.licenseType),
                  ),
                  const SizedBox(width: 16),
                  _buildInfoItem(
                    Icons.attach_money,
                    inquiry.budgetYuan,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 对方信息
              Row(
                children: [
                  const Icon(Icons.person, size: 14, color: AppColors.text3),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      role == 'buyer'
                          ? '卖方: ${inquiry.sellerName ?? '-'}'
                          : '买方: ${inquiry.buyerName ?? '-'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                      ),
                    ),
                  ),
                  const Icon(Icons.access_time, size: 14, color: AppColors.text3),
                  const SizedBox(width: 4),
                  Text(
                    formatDate(inquiry.createdAt),
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTag(String? status) {
    Color bgColor;
    Color textColor;
    switch (status) {
      case InquiryStatus.pending:
        bgColor = AppColors.warning.withOpacity(0.1);
        textColor = AppColors.warning;
      case InquiryStatus.accepted:
        bgColor = AppColors.success.withOpacity(0.1);
        textColor = AppColors.success;
      case InquiryStatus.rejected:
        bgColor = AppColors.danger.withOpacity(0.1);
        textColor = AppColors.danger;
      case InquiryStatus.deal:
        bgColor = AppColors.primary.withOpacity(0.1);
        textColor = AppColors.primary;
      case InquiryStatus.closed:
        bgColor = AppColors.fill;
        textColor = AppColors.text3;
      default:
        bgColor = AppColors.fill;
        textColor = AppColors.text2;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        InquiryStatus.label(status),
        style: TextStyle(fontSize: 12, color: textColor),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.text3),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppColors.text2),
        ),
      ],
    );
  }
}
