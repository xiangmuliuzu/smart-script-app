/// 版权证书列表页（App 端）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/common_views.dart';
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
    extends ConsumerState<CopyrightCertificateListPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = ref.read(copyrightProvider);
    await provider.loadCertificates(
      workName: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
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
        title: const Text('版权证书'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // 搜索栏
          _buildSearchBar(),
          // 列表
          Expanded(
            child: _buildListView(provider),
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
          hintText: '搜索作品名称',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _loadData();
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
        onSubmitted: (_) => _loadData(),
      ),
    );
  }

  Widget _buildListView(provider) {
    if (provider.certificateLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.certificateError != null) {
      return CommonViews.errorView(
        message: provider.certificateError!,
        onRetry: _loadData,
      );
    }

    if (provider.certificates.isEmpty) {
      return CommonViews.emptyView(
        icon: Icons.workspace_premium_outlined,
        message: '暂无证书记录',
        actionText: '去申请',
        onAction: () => context.push(RoutePath.copyrightApply),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: provider.certificates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = provider.certificates[index];
          return _buildCertificateCard(item);
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
          '${RoutePath.copyrightCertificateDetail}/${item.certId}',
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
              // 标题行
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
                      color: Color(0xFF1890FF),
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
              // 信息行
              _buildInfoRow(Icons.person_outline, '权利人：${item.userName}'),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.event_available, '签发时间：${item.certTime ?? '-'}'),
              if (item.blockchainHash != null && item.blockchainHash!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                  Icons.vpn_key_outlined,
                  '区块链哈希：${item.blockchainHash!.length > 16 ? item.blockchainHash!.substring(0, 16) : item.blockchainHash!}${item.blockchainHash!.length > 16 ? '...' : ''}',
                ),
              ],
              // 查看按钮
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push(
                      '${RoutePath.copyrightCertificateDetail}/${item.certId}',
                    ),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('查看详情'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
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
