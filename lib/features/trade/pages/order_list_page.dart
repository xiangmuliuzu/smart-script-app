import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../user_center/data/paged_data.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 订单列表页（双Tab：买方订单 / 作者订单，状态筛选）。
class OrderListPage extends ConsumerStatefulWidget {
  const OrderListPage({super.key});

  @override
  ConsumerState<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends ConsumerState<OrderListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// 每个 Tab 当前选中的状态筛选（null = 全部）
  String? _buyerStatus;
  String? _sellerStatus;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentRole => _tabController.index == 0 ? 'buyer' : 'seller';

  String? get _currentStatus =>
      _tabController.index == 0 ? _buyerStatus : _sellerStatus;

  void _setStatus(String? status) {
    if (_tabController.index == 0) {
      _buyerStatus = status;
    } else {
      _sellerStatus = status;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final params = AppOrderListParams(
      role: _currentRole,
      status: _currentStatus,
    );
    final listAsync = ref.watch(appOrderListProvider(params));

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的订单'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: '买方订单'),
            Tab(text: '作者订单'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildStatusFilter(),
          Expanded(child: _buildList(listAsync)),
        ],
      ),
    );
  }

  /// 状态筛选横向滚动
  Widget _buildStatusFilter() {
    const statuses = [
      (null, '全部'),
      (OrderStatus.confirmed, '已确认'),
      (OrderStatus.delivering, '交割中'),
      (OrderStatus.completed, '已完成'),
      (OrderStatus.cancelled, '已取消'),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: statuses.length,
        itemBuilder: (_, i) {
          final (value, label) = statuses[i];
          final selected = _currentStatus == value;
          return GestureDetector(
            onTap: () => _setStatus(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : Colors.grey.shade700,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(AsyncValue<PagedData<Order>> listAsync) {
    return listAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (paged) {
        if (paged.list.isEmpty) {
          return const Center(child: Text('暂无订单', style: TextStyle(color: AppColors.text3)));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(appOrderListProvider(AppOrderListParams(
            role: _currentRole,
            status: _currentStatus,
          ))),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: paged.list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildOrderItem(paged.list[i]),
          ),
        );
      },
    );
  }

  Widget _buildOrderItem(Order order) {
    return GestureDetector(
      onTap: () => context.push(
        '${RoutePath.orderDetail}?id=${order.orderId}',
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：作品名 + 状态
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.workTitle ?? '未知作品',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusTag(order.status),
              ],
            ),
            const SizedBox(height: 8),
            // 第二行：金额 + 订单号
            Row(
              children: [
                Text(
                  order.amountYuan,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  order.orderNo ?? '',
                  style: const TextStyle(fontSize: 11, color: AppColors.text3),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 第三行：授权类型 + 时间
            Row(
              children: [
                Text(
                  LicenseType.label(order.licenseType),
                  style: const TextStyle(fontSize: 12, color: AppColors.text2),
                ),
                const Spacer(),
                Text(
                  _formatDate(order.createdAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.text3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTag(String? status) {
    final Color color;
    switch (status) {
      case OrderStatus.confirmed:
        color = AppColors.primary;
      case OrderStatus.delivering:
        color = AppColors.warning;
      case OrderStatus.completed:
        color = AppColors.success;
      case OrderStatus.cancelled:
        color = AppColors.text3;
      default:
        color = AppColors.text2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        OrderStatus.label(status),
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
