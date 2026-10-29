/// 版权交割列表页（App 端）。
///
/// 从版权管理入口进入，展示付款后产生的交割记录，支持状态/角色筛选与下拉刷新。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/route_paths.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/copyright_models.dart';
import '../data/copyright_providers.dart';
import '../providers/copyright_provider.dart';

/// 版权交割列表页。
class CopyrightDeliveryListPage extends ConsumerStatefulWidget {
  const CopyrightDeliveryListPage({super.key});

  @override
  ConsumerState<CopyrightDeliveryListPage> createState() =>
      _CopyrightDeliveryListPageState();
}

class _CopyrightDeliveryListPageState
    extends ConsumerState<CopyrightDeliveryListPage> {
  String? _statusFilter;
  String? _deliveryRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    await ref.read(copyrightProvider).loadDeliveries(
          role: _deliveryRole,
          status: _statusFilter,
        );
  }

  Future<void> _onRefresh() async {
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(copyrightProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('版权交割'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          _buildDeliveryInfoCard(),
          _buildDeliveryFilterBar(),
          Expanded(child: _buildDeliveryListView(provider)),
        ],
      ),
    );
  }

  Widget _buildDeliveryInfoCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '什么是版权交割？',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '版权交割是指合同签署并付款后，卖方交付版权证书、作品源文件等约定内容，买方确认收货后订单完成。',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade800,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryFilterBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildDeliveryFilterChip('全部', null),
                const SizedBox(width: 8),
                _buildDeliveryFilterChip('待上传', 'pending_upload'),
                const SizedBox(width: 8),
                _buildDeliveryFilterChip('待确认', 'pending_confirm'),
                const SizedBox(width: 8),
                _buildDeliveryFilterChip('已完成', 'completed'),
                const SizedBox(width: 8),
                _buildDeliveryFilterChip('已取消', 'cancelled'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _deliveryRole == null
                        ? '全部角色'
                        : _deliveryRole == 'seller'
                            ? '我转出的'
                            : '我获得的',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
            onSelected: (value) {
              setState(() {
                _deliveryRole = value.isEmpty ? null : value;
              });
              _loadData();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: '', child: Text('全部角色')),
              const PopupMenuItem(value: 'seller', child: Text('我转出的')),
              const PopupMenuItem(value: 'buyer', child: Text('我获得的')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryFilterChip(String label, String? status) {
    final isSelected = _statusFilter == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _statusFilter = selected ? status : null;
        });
        _loadData();
      },
      selectedColor: AppColors.primary.withOpacity(0.2),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        fontSize: 13,
        color: isSelected ? AppColors.primary : AppColors.text2,
      ),
    );
  }

  Widget _buildDeliveryListView(CopyrightProvider provider) {
    if (provider.deliveryLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.deliveryError != null) {
      return ErrorView(
        message: provider.deliveryError!,
        onRetry: _loadData,
      );
    }

    if (provider.deliveries.isEmpty) {
      return const EmptyView(message: '暂无交割记录');
    }

    return Container(
      color: AppColors.pageBackground,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: provider.deliveries.length,
          itemBuilder: (context, index) {
            final delivery = provider.deliveries[index];
            return _buildDeliveryCard(delivery);
          },
        ),
      ),
    );
  }

  Widget _buildDeliveryCard(CopyrightDelivery delivery) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(
            '${RoutePath.copyrightApplicationDetail}?id=${delivery.deliveryId}&type=delivery',
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      delivery.deliveryNo,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text3,
                      ),
                    ),
                    _buildDeliveryStatusBadge(delivery.status),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  delivery.workTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: AppColors.text3),
                    const SizedBox(width: 4),
                    Text(
                      '买方：${delivery.buyerName} | 卖方：${delivery.sellerName}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.monetization_on_outlined, size: 14, color: AppColors.text3),
                    const SizedBox(width: 4),
                    Text(
                      '¥${delivery.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.shield_outlined, size: 14, color: AppColors.text3),
                    const SizedBox(width: 4),
                    Text(
                      delivery.licenseType.licenseTypeName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  delivery.createTime,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'pending_upload':
        color = Colors.orange;
        break;
      case 'pending_confirm':
        color = Colors.blue;
        break;
      case 'completed':
        color = Colors.green;
        break;
      case 'cancelled':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.deliveryStatusName,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
