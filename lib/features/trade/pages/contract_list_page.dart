import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../user_center/data/paged_data.dart';
import '../data/contract_providers.dart';
import '../data/trade_models.dart';

/// 我的合同列表页。
///
/// 双 Tab：买方合同 / 作者合同，叠加状态筛选（全部 / 待签署 / 部分签署 / 已完成）。
/// 每条展示合同号、作品、金额、双方签署状态；点击进入合同详情页
/// （内容预览、PDF 下载、签署状态、签署均复用 [ContractSignPage]）。
class ContractListPage extends ConsumerStatefulWidget {
  const ContractListPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<ContractListPage> createState() => _ContractListPageState();
}

class _ContractListPageState extends ConsumerState<ContractListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// 每个 Tab 当前选中的状态筛选（null = 全部），切换 Tab 后各自保留。
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
    setState(() {
      if (_tabController.index == 0) {
        _buyerStatus = status;
      } else {
        _sellerStatus = status;
      }
    });
  }

  AppContractListParams get _params =>
      AppContractListParams(role: _currentRole, status: _currentStatus);

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(contractListProvider(_params));

    return Scaffold(
      appBar: AppBar(
        title: widget.embedded ? null : const Text('我的合同'),
        automaticallyImplyLeading: !widget.embedded,
        primary: !widget.embedded,
        toolbarHeight: widget.embedded ? 0 : kToolbarHeight,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: '买方合同'),
            Tab(text: '作者合同'),
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
    const statuses = <(String?, String)>[
      (null, '全部'),
      (ContractStatus.pending, '待签署'),
      (ContractStatus.partialSigned, '部分签署'),
      (ContractStatus.completed, '已完成'),
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

  Widget _buildList(AsyncValue<PagedData<ContractDetail>> listAsync) {
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
              onPressed: () => ref.invalidate(contractListProvider(_params)),
              child: const Text('点击重试'),
            ),
          ],
        ),
      ),
      data: (paged) {
        if (paged.list.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(contractListProvider(_params)),
            child: ListView(
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.28),
                Icon(Icons.description_outlined,
                    size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text('暂无合同',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.text3)),
                const SizedBox(height: 6),
                const Text('订单生成后会自动创建待签合同',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.text3)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(contractListProvider(_params)),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: paged.list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildContractItem(paged.list[i]),
          ),
        );
      },
    );
  }

  Widget _buildContractItem(ContractDetail c) {
    // 按当前 Tab 角色判定"我方"签署状态与对方名称
    final bool mySigned =
        _currentRole == 'buyer' ? c.isBuyerSigned : c.isSellerSigned;
    final String counterparty = _currentRole == 'buyer'
        ? (c.sellerName ?? '卖方')
        : (c.buyerName ?? '买方');
    final String counterpartyLabel = _currentRole == 'buyer' ? '卖方' : '买方';
    final bool canSign = !c.isCompleted && !mySigned;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(
        '${RoutePath.contractSign}?orderId=${c.orderId ?? 0}',
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
            // 第一行：作品名 + 合同状态
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.workTitle ?? '合同 ${c.contractNo ?? ''}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusTag(c.status),
              ],
            ),
            const SizedBox(height: 8),
            // 第二行：金额 + 合同号
            Row(
              children: [
                Text(
                  c.amountYuan,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                if (c.licenseType != null && c.licenseType!.isNotEmpty)
                  Text(
                    LicenseType.label(c.licenseType),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.text2),
                  ),
                const Spacer(),
                Text(
                  c.contractNo ?? '',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.text3),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 第三行：双方签署标记 + 对方 + 时间
            Row(
              children: [
                _signTag('买方', c.isBuyerSigned),
                const SizedBox(width: 6),
                _signTag('卖方', c.isSellerSigned),
                const Spacer(),
                Text(
                  c.createdAt ?? '',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.text3),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 第四行：对方 + 操作提示
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$counterpartyLabel：$counterparty',
                    style: const TextStyle(fontSize: 12, color: AppColors.text2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canSign)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('去签署',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  )
                else if (c.isCompleted)
                  const Text('查看 / 下载 PDF',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.text3)),
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
      case ContractStatus.pending:
        color = AppColors.warning;
      case ContractStatus.partialSigned:
        color = AppColors.primary;
      case ContractStatus.completed:
        color = AppColors.success;
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
        ContractStatus.label(status),
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _signTag(String party, bool signed) {
    final color = signed ? AppColors.success : AppColors.text3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: signed
            ? AppColors.success.withOpacity(0.1)
            : AppColors.fill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$party ${signed ? '✓' : '○'}',
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}
