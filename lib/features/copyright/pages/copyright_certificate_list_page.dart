/// 版权证书列表页（App 端）。
///
/// 分栏：我申请的（内容域正式证书） / 购买获得（交易域交割 cert 材料）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/common_views.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/copyright_models.dart';
import '../data/copyright_providers.dart';

/// 版权证书列表页
class CopyrightCertificateListPage extends ConsumerStatefulWidget {
  const CopyrightCertificateListPage({super.key});

  @override
  ConsumerState<CopyrightCertificateListPage> createState() =>
      _CopyrightCertificateListPageState();
}

class _CopyrightCertificateListPageState
    extends ConsumerState<CopyrightCertificateListPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentTab();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
    _loadCurrentTab();
  }

  bool get _isPurchasedTab => _tabController.index == 1;

  Future<void> _loadCurrentTab() async {
    final provider = ref.read(copyrightProvider);
    final keyword = _searchController.text.trim();
    if (_isPurchasedTab) {
      await provider.loadPurchasedCopyrights(
        keyword: keyword.isEmpty ? null : keyword,
      );
    } else {
      await provider.loadCertificates(
        workName: keyword.isEmpty ? null : keyword,
      );
    }
  }

  Future<void> _onRefresh() async {
    await _loadCurrentTab();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(copyrightProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('版权证书'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.text1,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: '我申请的'),
            Tab(text: '购买获得'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAppliedList(provider),
                _buildPurchasedList(provider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: _isPurchasedTab ? '搜索作品名称 / 卖家 / 材料名' : '搜索作品名称',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    _loadCurrentTab();
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _loadCurrentTab(),
      ),
    );
  }

  Widget _buildAppliedList(provider) {
    if (provider.certificateLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.certificateError != null) {
      return ErrorView(
        message: provider.certificateError!,
        onRetry: _loadCurrentTab,
      );
    }

    if (provider.certificates.isEmpty) {
      return const EmptyView(
        icon: Icons.workspace_premium_outlined,
        message: '暂无证书记录',
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: provider.certificates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = provider.certificates[index] as CopyrightCert;
          return _buildCertificateCard(item);
        },
      ),
    );
  }

  Widget _buildPurchasedList(provider) {
    if (provider.purchasedLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.purchasedError != null) {
      return ErrorView(
        message: provider.purchasedError!,
        onRetry: _loadCurrentTab,
      );
    }

    if (provider.purchasedMaterials.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shopping_bag_outlined,
                size: 56,
                color: AppColors.text3,
              ),
              const SizedBox(height: 12),
              const Text(
                '暂无购买获得的版权材料',
                style: TextStyle(color: AppColors.text3),
              ),
              const SizedBox(height: 8),
              Text(
                '确认收货后，且卖方交割时上传了版权证书才会出现',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text3.withOpacity(0.85),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: provider.purchasedMaterials.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item =
              provider.purchasedMaterials[index] as BuyerCopyrightMaterial;
          return _buildPurchasedCard(item);
        },
      ),
    );
  }

  Widget _buildCertificateCard(CopyrightCert item) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.push(
          RoutePath.copyrightCertificateDetailUrl(item.certId),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.workName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '证书编号：${item.certNo}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(item.status),
                ],
              ),
              const SizedBox(height: 16),
              _buildInfoRow(Icons.person_outline, '权利人：${item.userName}'),
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.event_available,
                '签发时间：${item.certTime ?? '-'}',
              ),
              if (item.blockchainHash != null &&
                  item.blockchainHash!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                  Icons.vpn_key_outlined,
                  '区块链哈希：${item.blockchainHash!.length > 16 ? item.blockchainHash!.substring(0, 16) : item.blockchainHash!}${item.blockchainHash!.length > 16 ? '...' : ''}',
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push(
                      RoutePath.copyrightCertificateDetailUrl(item.certId),
                    ),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('查看详情'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.text1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPurchasedCard(BuyerCopyrightMaterial item) {
    final title =
        item.workTitle.isEmpty ? '作品' : '《${item.workTitle}》';
    final orderText = item.orderNo.isEmpty
        ? (item.orderId > 0 ? '#${item.orderId}' : '-')
        : item.orderNo;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.push(
          RoutePath.buyerCopyrightDetailUrl(item.fileId),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '材料：${item.fileName.isEmpty ? '未命名材料' : item.fileName}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                      ),
                    ),
                    child: const Text(
                      '购买获得',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.text1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildInfoRow(
                Icons.storefront_outlined,
                '卖家：${item.sellerName.isEmpty ? '-' : item.sellerName}',
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.event_available,
                '交割时间：${item.deliveryTime.isEmpty ? '-' : item.deliveryTime}',
              ),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.receipt_long_outlined, '订单号：$orderText'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push(
                      RoutePath.buyerCopyrightDetailUrl(item.fileId),
                    ),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('预览 / 下载'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.text1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case CopyrightCertStatus.pending:
        color = const Color(0xFFFFA940);
        label = '申请中';
        break;
      case CopyrightCertStatus.issued:
        color = const Color(0xFF52C41A);
        label = '已签发';
        break;
      case CopyrightCertStatus.expired:
        color = const Color(0xFF8C8C8C);
        label = '已失效';
        break;
      default:
        color = AppColors.text2;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.text3),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.text2,
            ),
          ),
        ),
      ],
    );
  }
}
