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
  bool _isLoading = false;

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
    setState(() { _isLoading = true; });
    // 延迟恢复 loading，让用户看到反馈
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() { _isLoading = false; });
    });
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
          if (_isLoading)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildList(listAsync)),
        ],
      ),
    );
  }

  /// 状态筛选横向滚动
  Widget _buildStatusFilter() {
    const statuses = [
      (null, '全部'),
      (OrderStatus.confirmed, '待签署'),
      (OrderStatus.paying, '付款中'),
      (OrderStatus.delivering, '交割中'),
      (OrderStatus.completed, '已完成'),
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
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.text3),
            const SizedBox(height: 8),
            Text('加载失败: $e', style: const TextStyle(color: AppColors.text3)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(appOrderListProvider(AppOrderListParams(
                role: _currentRole, status: _currentStatus,
              ))),
              child: const Text('点击重试'),
            ),
          ],
        ),
      ),
      data: (paged) {
        if (paged.list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text('暂无订单', style: TextStyle(fontSize: 14, color: AppColors.text3)),
                const SizedBox(height: 6),
                const Text('去聊天中接受报价即可生成订单', style: TextStyle(fontSize: 12, color: AppColors.text3)),
              ],
            ),
          );
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
    // 根据角色显示对方名称
    final String counterparty = _currentRole == 'buyer'
        ? (order.sellerName ?? '用户${order.sellerId}')
        : (order.buyerName ?? '用户${order.buyerId}');
    final String counterpartyLabel = _currentRole == 'buyer' ? '卖方' : '买方';
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
            // 第三行：授权类型 + 对方 + 时间
            Row(
              children: [
                Text(
                  LicenseType.label(order.licenseType),
                  style: const TextStyle(fontSize: 12, color: AppColors.text2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$counterpartyLabel：$counterparty',
                    style: const TextStyle(fontSize: 12, color: AppColors.text2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
      case OrderStatus.paying:
        color = AppColors.warning;
      case OrderStatus.escrowPending:
        color = AppColors.warning;
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
