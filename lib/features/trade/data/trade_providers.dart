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

// ==================== 报价/议价 Providers ====================

/// 报价列表查询参数
class QuoteListParams {
  final int? inquiryId;
  final String? role;
  final String? status;
  final int pageNum;
  final int pageSize;

  const QuoteListParams({
    this.inquiryId,
    this.role,
    this.status,
    this.pageNum = 1,
    this.pageSize = 20,
  });
}

/// 报价分页列表
final quoteListProvider = FutureProvider.autoDispose
    .family<PagedData<Quote>, QuoteListParams>(
  (ref, params) => ref.watch(tradeRepositoryProvider).pageQuotes(
        inquiryId: params.inquiryId,
        role: params.role,
        status: params.status,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
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

// ==================== 订单 Providers ====================

/// 订单列表查询参数
class OrderListParams {
  final String? role;       // buyer / seller / null(全部)
  final String? status;
  final String? keyword;
  final int pageNum;
  final int pageSize;

  const OrderListParams({
    this.role,
    this.status,
    this.keyword,
    this.pageNum = 1,
    this.pageSize = 20,
  });

  OrderListParams copyWith({
    String? role,
    String? status,
    String? keyword,
    int? pageNum,
    int? pageSize,
  }) {
    return OrderListParams(
      role: role ?? this.role,
      status: status ?? this.status,
      keyword: keyword ?? this.keyword,
      pageNum: pageNum ?? this.pageNum,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

/// 订单分页列表
final orderListProvider = FutureProvider.autoDispose
    .family<PagedData<Order>, OrderListParams>(
  (ref, params) => ref.watch(tradeRepositoryProvider).pageOrders(
        role: params.role,
        status: params.status,
        keyword: params.keyword,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
);

/// 订单详情
final orderDetailProvider = FutureProvider.autoDispose.family<Order, int>(
  (ref, orderId) => ref.watch(tradeRepositoryProvider).orderDetail(orderId),
);

// ==================== 合作记录 Providers ====================

/// 合作记录列表查询参数
class CooperationListParams {
  final String? source;     // online / offline / null(全部)
  final int? workId;
  final int pageNum;
  final int pageSize;

  const CooperationListParams({
    this.source,
    this.workId,
    this.pageNum = 1,
    this.pageSize = 20,
  });
}

/// 合作记录分页列表
final cooperationListProvider = FutureProvider.autoDispose
    .family<PagedData<Cooperation>, CooperationListParams>(
  (ref, params) => ref.watch(tradeRepositoryProvider).pageCooperations(
        source: params.source,
        workId: params.workId,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
);

// ==================== 商务跟进 Providers ====================

/// 跟进记录列表查询参数
class FollowUpListParams {
  final int? partnerId;
  final int? workId;
  final int pageNum;
  final int pageSize;

  const FollowUpListParams({
    this.partnerId,
    this.workId,
    this.pageNum = 1,
    this.pageSize = 20,
  });
}

/// 跟进记录分页列表
final followUpListProvider = FutureProvider.autoDispose
    .family<PagedData<BusinessFollow>, FollowUpListParams>(
  (ref, params) => ref.watch(tradeRepositoryProvider).pageFollowUps(
        partnerId: params.partnerId,
        workId: params.workId,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
);

// ==================== 交易作品 Providers ====================

/// 交易作品列表查询参数
class TradeWorkListParams {
  final String? keyword;
  final bool? tradeEnabled;
  final int pageNum;
  final int pageSize;

  const TradeWorkListParams({
    this.keyword,
    this.tradeEnabled,
    this.pageNum = 1,
    this.pageSize = 20,
  });
}

/// 交易作品分页列表
final tradeWorkListProvider = FutureProvider.autoDispose
    .family<PagedData<TradeWork>, TradeWorkListParams>(
  (ref, params) => ref.watch(tradeRepositoryProvider).pageTradeWorks(
        keyword: params.keyword,
        tradeEnabled: params.tradeEnabled,
        pageNum: params.pageNum,
        pageSize: params.pageSize,
      ),
);

/// 交易作品详情
final tradeWorkDetailProvider = FutureProvider.autoDispose.family<TradeWork, int>(
  (ref, workId) => ref.watch(tradeRepositoryProvider).tradeWorkDetail(workId),
);

// ==================== 订单 Providers ====================

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
