import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../user_center/data/paged_data.dart';
import 'trade_models.dart';
import 'trade_repository.dart';

/// C 交易域依赖注入（复用框架层网络栈）。

final tradeRepositoryProvider = Provider<TradeRepository>(
  (ref) => TradeRepository(ref.watch(apiClientProvider)),
);

// ==================== 询盘 Providers ====================

/// 询盘列表查询参数
class InquiryListParams {
  final String? role;       // buyer / seller / null(全部)
  final String? status;
  final String? keyword;
  final int pageNum;
  final int pageSize;

  const InquiryListParams({
    this.role,
    this.status,
    this.keyword,
    this.pageNum = 1,
    this.pageSize = 20,
  });

  InquiryListParams copyWith({
    String? role,
    String? status,
    String? keyword,
    int? pageNum,
    int? pageSize,
  }) {
    return InquiryListParams(
      role: role ?? this.role,
      status: status ?? this.status,
      keyword: keyword ?? this.keyword,
      pageNum: pageNum ?? this.pageNum,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InquiryListParams &&
        other.role == role &&
        other.status == status &&
        other.keyword == keyword &&
        other.pageNum == pageNum &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(role, status, keyword, pageNum, pageSize);
}

/// 询盘分页列表
final inquiryListProvider = FutureProvider.autoDispose
    .family<PagedData<Inquiry>, InquiryListParams>(
  (ref, params) => ref.watch(tradeRepositoryProvider).pageInquiries(
        role: params.role,
        status: params.status,
        keyword: params.keyword,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
);

/// 询盘详情
final inquiryDetailProvider = FutureProvider.autoDispose.family<Inquiry, int>(
  (ref, inquiryId) => ref.watch(tradeRepositoryProvider).inquiryDetail(inquiryId),
);

/// 作品确权状态（按 workId）：驱动发起询盘页是否展示授权类型选择器
final copyrightStatusProvider = FutureProvider.autoDispose.family<bool, int>(
  (ref, workId) => ref.watch(tradeRepositoryProvider).getCopyrightStatus(workId),
);

// ==================== 报价/议价 Providers（APP端） ====================

/// 按询盘ID查询报价列表
final appQuoteListProvider = FutureProvider.autoDispose
    .family<List<Quote>, int>(
  (ref, inquiryId) => ref.watch(tradeRepositoryProvider).listQuotesByInquiry(inquiryId),
);

/// 按询盘ID查询最新报价（用于聊天页议价卡片）
final latestQuoteProvider = FutureProvider.autoDispose
    .family<Quote?, int>(
  (ref, inquiryId) => ref.watch(tradeRepositoryProvider).getLatestQuote(inquiryId),
);

// ==================== 订单 Providers（APP端） ====================

/// APP订单列表查询参数
class AppOrderListParams {
  final String role;
  final String? status;
  final int pageNum;
  final int pageSize;

  const AppOrderListParams({
    required this.role,
    this.status,
    this.pageNum = 1,
    this.pageSize = 10,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppOrderListParams &&
          role == other.role &&
          status == other.status &&
          pageNum == other.pageNum &&
          pageSize == other.pageSize;

  @override
  int get hashCode => Object.hash(role, status, pageNum, pageSize);
}

/// APP订单分页列表
final appOrderListProvider = FutureProvider.autoDispose
    .family<PagedData<Order>, AppOrderListParams>(
  (ref, params) => ref.watch(tradeRepositoryProvider).appPageOrders(
        role: params.role,
        status: params.status,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
);

/// APP订单详情
final appOrderDetailProvider = FutureProvider.autoDispose.family<Order, int>(
  (ref, orderId) => ref.watch(tradeRepositoryProvider).appOrderDetail(orderId),
);

// ==================== 财务域 Providers ====================

/// 收益总览
final incomeOverviewProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(tradeRepositoryProvider).incomeOverview(),
);

/// 收益明细查询参数
class BillRecordListParams {
  final String? billType;
  final int pageNum;
  final int pageSize;
  const BillRecordListParams({this.billType, this.pageNum = 1, this.pageSize = 20});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillRecordListParams &&
          billType == other.billType &&
          pageNum == other.pageNum &&
          pageSize == other.pageSize;

  @override
  int get hashCode => Object.hash(billType, pageNum, pageSize);
}

/// 收益明细列表
final billRecordListProvider = FutureProvider.autoDispose
    .family<PagedData<BillRecord>, BillRecordListParams>(
  (ref, params) => ref.watch(tradeRepositoryProvider).pageBillRecords(
        billType: params.billType,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
);
