import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'contract_repository.dart';
import 'trade_models.dart';

/// 合同域依赖注入。

final contractRepositoryProvider = Provider<ContractRepository>(
  (ref) => ContractRepository(ref.watch(apiClientProvider)),
);

/// 按订单 ID 取合同详情
final contractByOrderProvider =
    FutureProvider.autoDispose.family<ContractDetail?, int>(
  (ref, orderId) =>
      ref.watch(contractRepositoryProvider).getContractByOrder(orderId),
);
