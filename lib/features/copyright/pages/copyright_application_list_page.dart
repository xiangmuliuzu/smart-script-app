/// 版权申请列表页（App 端）。
///
/// 展示我的版权申请记录，支持筛选、搜索、下拉刷新。
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

/// 版权申请列表页。
class CopyrightApplicationListPage extends ConsumerStatefulWidget {
  const CopyrightApplicationListPage({super.key});

  @override
  ConsumerState<CopyrightApplicationListPage> createState() =>
      _CopyrightApplicationListPageState();
}

class _CopyrightApplicationListPageState
    extends ConsumerState<CopyrightApplicationListPage> {
  String? _statusFilter;
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
    await ref.read(copyrightProvider).loadApplications(
          status: _statusFilter,
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
        title: const Text('申请列表'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => context.push(RoutePath.copyrightForm),
            tooltip: '新建申请',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildApplicationFilterBar(),
          Expanded(child: _buildApplicationListView(provider)),
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
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildApplicationFilterBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('全部', null),
          const SizedBox(width: 8),
          _buildFilterChip('待审核', CopyrightApplicationStatus.pending),
          const SizedBox(width: 8),
          _buildFilterChip('审核中', CopyrightApplicationStatus.reviewing),
          const SizedBox(width: 8),
          _buildFilterChip('已通过', CopyrightApplicationStatus.certificated),
          const SizedBox(width: 8),
          _buildFilterChip('已拒绝', CopyrightApplicationStatus.rejected),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? status) {
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

  Widget _buildApplicationListView(CopyrightProvider provider) {
    if (provider.applicationLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.applicationError != null) {
      return ErrorView(
        message: provider.applicationError!,
        onRetry: _loadData,
      );
    }

    if (provider.applications.isEmpty) {
      return const EmptyView(message: '暂无申请记录');
    }

    return Container(
      color: AppColors.pageBackground,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: provider.applications.length,
          itemBuilder: (context, index) {
            final app = provider.applications[index];
            return _buildApplicationCard(app);
          },
        ),
      ),
    );
  }

  Widget _buildApplicationCard(CopyrightApplication app) {
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
            RoutePath.copyrightApplicationDetailUrl(app.applyId),
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
                    Expanded(
                      child: Text(
                        app.workName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusBgColor(app.status),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getStatusIcon(app.status),
                            size: 14,
                            color: _getStatusColor(app.status),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            app.status.statusName,
                            style: TextStyle(
                              fontSize: 12,
                              color: _getStatusColor(app.status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.confirmation_number_outlined,
                        size: 14, color: AppColors.text3),
                    const SizedBox(width: 4),
                    Text(
                      app.applyNo,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.category_outlined,
                        size: 14, color: AppColors.text3),
                    const SizedBox(width: 4),
                    Text(
                      '${app.workType ?? '-'} | ${app.centerName}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 14, color: AppColors.text3),
                        const SizedBox(width: 4),
                        Text(
                          app.createTime ?? '-',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                    if (app.status == CopyrightApplicationStatus.pending)
                      TextButton(
                        onPressed: () => _confirmDelete(app),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('删除', style: TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(CopyrightApplication app) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除申请「${app.workName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteApplication(app.applyId);
    }
  }

  Future<void> _deleteApplication(int applyId) async {
    try {
      final provider = ref.read(copyrightProvider);
      await provider.deleteApplication(applyId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('删除成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case CopyrightApplicationStatus.pending:
        return const Color(0xFFFFA940);
      case CopyrightApplicationStatus.approved:
      case CopyrightApplicationStatus.submitted:
        return const Color(0xFF1890FF);
      case CopyrightApplicationStatus.reviewing:
        return const Color(0xFF722ED1);
      case CopyrightApplicationStatus.certificated:
        return const Color(0xFF52C41A);
      case CopyrightApplicationStatus.rejected:
        return const Color(0xFFF5222D);
      default:
        return AppColors.text2;
    }
  }

  Color _getStatusBgColor(String status) {
    return _getStatusColor(status).withOpacity(0.1);
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case CopyrightApplicationStatus.pending:
        return Icons.schedule;
      case CopyrightApplicationStatus.approved:
      case CopyrightApplicationStatus.submitted:
        return Icons.upload;
      case CopyrightApplicationStatus.reviewing:
        return Icons.hourglass_empty;
      case CopyrightApplicationStatus.certificated:
        return Icons.check_circle;
      case CopyrightApplicationStatus.rejected:
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }
}
