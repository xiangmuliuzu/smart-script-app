import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../user_center/data/paged_data.dart';
import 'contract_repository.dart';
import 'trade_models.dart';

/// 合同域依赖注入。

final contractRepositoryProvider = Provider<ContractRepository>(
  (ref) => ContractRepository(ref.watch(apiClientProvider)),
);

/// 合同列表查询参数（分页）。
class AppContractListParams {
  final String? role;
  final String? status;
  final int pageNum;
  final int pageSize;

  const AppContractListParams({
    this.role,
    this.status,
    this.pageNum = 1,
    this.pageSize = 10,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppContractListParams &&
          role == other.role &&
          status == other.status &&
          pageNum == other.pageNum &&
          pageSize == other.pageSize;

  @override
  int get hashCode => Object.hash(role, status, pageNum, pageSize);
}

/// 我的合同分页列表。
final contractListProvider = FutureProvider.autoDispose
    .family<PagedData<ContractDetail>, AppContractListParams>(
  (ref, params) => ref.watch(contractRepositoryProvider).listContracts(
        role: params.role,
        status: params.status,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
);

/// 按订单 ID 取合同详情
final contractByOrderProvider =
    FutureProvider.autoDispose.family<ContractDetail?, int>(
  (ref, orderId) =>
      ref.watch(contractRepositoryProvider).getContractByOrder(orderId),
);
