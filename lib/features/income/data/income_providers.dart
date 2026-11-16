import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_providers.dart';
import '../../user_center/data/paged_data.dart';
import 'income_models.dart';
import 'income_repository.dart';

final incomeRepositoryProvider = Provider<IncomeRepository>(
  (ref) => IncomeRepository(ref.watch(apiClientProvider)),
);

final myIncomeOverviewProvider =
    FutureProvider.autoDispose<IncomeOverview>((ref) async {
  final userId = ref.watch(
    authControllerProvider.select((s) => s.user?.userId),
  );
  if (userId == null) {
    return const IncomeOverview(
      totalIncome: 0,
      pendingSettleAmount: 0,
      availableAmount: 0,
    );
  }
  return ref.watch(incomeRepositoryProvider).overview();
});

final incomeStatsProvider =
    FutureProvider.autoDispose.family<IncomePeriodStats, String>((ref, period) async {
  final userId = ref.watch(
    authControllerProvider.select((s) => s.user?.userId),
  );
  if (userId == null) {
    return IncomePeriodStats(
      period: period,
      incomeAmount: 0,
      withdrawAmount: 0,
    );
  }
  return ref.watch(incomeRepositoryProvider).stats(period: period);
});

class IncomeDetailParams {
  const IncomeDetailParams({this.billType, this.pageNum = 1, this.pageSize = 20});

  final String? billType;
  final int pageNum;
  final int pageSize;

  @override
  bool operator ==(Object other) =>
      other is IncomeDetailParams &&
      other.billType == billType &&
      other.pageNum == pageNum &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(billType, pageNum, pageSize);
}

final incomeDetailListProvider = FutureProvider.autoDispose
    .family<PagedData<IncomeDetailItem>, IncomeDetailParams>((ref, params) async {
  final userId = ref.watch(
    authControllerProvider.select((s) => s.user?.userId),
  );
  if (userId == null) {
    return const PagedData<IncomeDetailItem>(total: 0, list: []);
  }
  return ref.watch(incomeRepositoryProvider).pageDetails(
        billType: params.billType,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      );
});

final incomeBillDetailProvider =
    FutureProvider.autoDispose.family<IncomeBillDetail, int>((ref, billId) async {
  final userId = ref.watch(
    authControllerProvider.select((s) => s.user?.userId),
  );
  if (userId == null || billId <= 0) {
    throw ApiException('未登录或账单无效');
  }
  return ref.watch(incomeRepositoryProvider).billDetail(billId);
});

class SettleListParams {
  const SettleListParams({this.status, this.pageNum = 1, this.pageSize = 20});

  final String? status;
  final int pageNum;
  final int pageSize;

  @override
  bool operator ==(Object other) =>
      other is SettleListParams &&
      other.status == status &&
      other.pageNum == pageNum &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(status, pageNum, pageSize);
}

final settleListProvider = FutureProvider.autoDispose
    .family<PagedData<IncomeSettleItem>, SettleListParams>((ref, params) async {
  final userId = ref.watch(
    authControllerProvider.select((s) => s.user?.userId),
  );
  if (userId == null) {
    return const PagedData<IncomeSettleItem>(total: 0, list: []);
  }
  return ref.watch(incomeRepositoryProvider).pageSettles(
        status: params.status,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      );
});

final settleDetailProvider =
    FutureProvider.autoDispose.family<IncomeSettleItem, int>((ref, settleId) async {
  final userId = ref.watch(
    authControllerProvider.select((s) => s.user?.userId),
  );
  if (userId == null || settleId <= 0) {
    throw ApiException('未登录或结算单无效');
  }
  return ref.watch(incomeRepositoryProvider).settleDetail(settleId);
});

class WithdrawListParams {
  const WithdrawListParams({this.status, this.pageNum = 1, this.pageSize = 20});

  final String? status;
  final int pageNum;
  final int pageSize;

  @override
  bool operator ==(Object other) =>
      other is WithdrawListParams &&
      other.status == status &&
      other.pageNum == pageNum &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(status, pageNum, pageSize);
}

final withdrawListProvider = FutureProvider.autoDispose
    .family<PagedData<WithdrawRecord>, WithdrawListParams>((ref, params) async {
  final userId = ref.watch(
    authControllerProvider.select((s) => s.user?.userId),
  );
  if (userId == null) {
    return const PagedData<WithdrawRecord>(total: 0, list: []);
  }
  return ref.watch(incomeRepositoryProvider).pageWithdraws(
        status: params.status,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      );
});
