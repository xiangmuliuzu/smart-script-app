import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'trade_models.dart';

/// C 交易域数据层。
///
/// 当前复用 admin 端点（`/api/v1/admin/trade/*`），后续后端创建 APP 专用接口时
/// 只需在 [ApiEndpoints] 替换路径，Repository 对外签名不变。
class TradeRepository {
  TradeRepository(this._api);

  final ApiClient _api;

  // ==================== 交易作品 ====================

  /// 交易作品列表（分页）。
  Future<PagedData<TradeWork>> pageTradeWorks({
    String? keyword,
    bool? tradeEnabled,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeWorks,
      query: _compact({
        'keyword': keyword,
        'tradeEnabled': tradeEnabled,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取交易作品列表失败');
    return PagedData.parse<TradeWork>(data, TradeWork.fromJson);
  }

  /// 交易作品详情。
  Future<TradeWork> tradeWorkDetail(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeWorkById(workId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取交易作品详情失败');
    return TradeWork.fromJson(data);
  }

  // ==================== 询盘 ====================

  /// 询盘列表（分页）。
  ///
  /// [role] 可选：buyer（我发起的）/ seller（我收到的）/ 空（全部）。
  Future<PagedData<Inquiry>> pageInquiries({
    String? role,
    String? status,
    String? keyword,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeInquiryList,
      query: _compact({
        'role': role,
        'status': status,
        'keyword': keyword,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取询盘列表失败');
    return PagedData.parse<Inquiry>(data, Inquiry.fromJson);
  }

  /// 询盘详情。
  Future<Inquiry> inquiryDetail(int inquiryId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeInquiryDetail(inquiryId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取询盘详情失败');
    return Inquiry.fromJson(data);
  }

  /// 创建询盘。
  Future<Inquiry> createInquiry(Inquiry inquiry) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.adminTradeInquiry,
      data: inquiry.toJson(),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('创建询盘失败');
    return Inquiry.fromJson(data);
  }

  /// 接受询盘。
  Future<void> acceptInquiry(int inquiryId) async {
    await _api.put<void>(
      ApiEndpoints.adminTradeInquiryAccept(inquiryId),
    );
  }

  /// 拒绝询盘。
  Future<void> rejectInquiry(int inquiryId) async {
    await _api.put<void>(
      ApiEndpoints.adminTradeInquiryReject(inquiryId),
    );
  }

  /// 关闭询盘。
  Future<void> closeInquiry(int inquiryId) async {
    await _api.put<void>(
      ApiEndpoints.adminTradeInquiryClose(inquiryId),
    );
  }

  // ==================== 报价/议价 ====================

  /// 报价列表（分页）。
  Future<PagedData<Quote>> pageQuotes({
    int? inquiryId,
    String? role,
    String? status,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeQuoteList,
      query: _compact({
        'inquiryId': inquiryId,
        'role': role,
        'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取报价列表失败');
    return PagedData.parse<Quote>(data, Quote.fromJson);
  }

  /// 创建报价（卖方出价）。
  Future<Quote> createQuote(Quote quote) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.adminTradeQuote,
      data: quote.toJson(),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('创建报价失败');
    return Quote.fromJson(data);
  }

  /// 买方议价。
  Future<Quote> counterOffer(Quote quote) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.adminTradeQuoteCounterOffer,
      data: quote.toJson(),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('发起议价失败');
    return Quote.fromJson(data);
  }

  /// 修改报价。
  Future<void> modifyQuote(int quoteId, Quote quote) async {
    await _api.put<void>(
      ApiEndpoints.adminTradeQuoteById(quoteId),
      data: quote.toJson(),
    );
  }

  /// 接受报价（生成订单）。
  Future<Order> acceptQuote(int quoteId) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.adminTradeQuoteAccept(quoteId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('接受报价失败');
    return Order.fromJson(data);
  }

  /// 拒绝报价。
  Future<void> rejectQuote(int quoteId) async {
    await _api.put<void>(
      ApiEndpoints.adminTradeQuoteReject(quoteId),
    );
  }

  /// 卖方接受买方议价。
  Future<Order> sellerAcceptQuote(int quoteId) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.adminTradeQuoteSellerAccept(quoteId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('接受议价失败');
    return Order.fromJson(data);
  }

  /// 卖方拒绝买方议价。
  Future<void> sellerRejectQuote(int quoteId) async {
    await _api.put<void>(
      ApiEndpoints.adminTradeQuoteSellerReject(quoteId),
    );
  }

  // ==================== 报价/议价（APP端） ====================

  /// 报价列表（按询盘ID查询，APP端）。
  Future<List<Quote>> listQuotesByInquiry(int inquiryId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appQuoteList,
      query: {'inquiryId': inquiryId},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取报价列表失败');
    final list = data['list'] as List<dynamic>? ?? [];
    return list.map((e) => Quote.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 创建报价（卖方出价，APP端）。
  Future<Quote> appCreateQuote(Quote quote) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.appQuoteCreate,
      data: quote.toJson(),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('创建报价失败');
    return Quote.fromJson(data);
  }

  /// 买方议价（APP端）。
  Future<Quote> appCounterOffer(Quote quote) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.appQuoteCounterOffer,
      data: quote.toJson(),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('发起议价失败');
    return Quote.fromJson(data);
  }

  /// 修改报价（APP端）。
  Future<void> appModifyQuote(int quoteId, Quote quote) async {
    await _api.put<void>(
      ApiEndpoints.appQuoteModify(quoteId),
      data: quote.toJson(),
    );
  }

  /// 接受报价（APP端）。
  Future<Map<String, dynamic>> appAcceptQuote(int quoteId) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.appQuoteAccept(quoteId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('接受报价失败');
    return data;
  }

  /// 拒绝报价（APP端）。
  Future<void> appRejectQuote(int quoteId) async {
    await _api.put<void>(
      ApiEndpoints.appQuoteReject(quoteId),
    );
  }

  /// 查询某询盘下最新报价（用于聊天页议价卡片）。
  Future<Quote?> getLatestQuote(int inquiryId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appQuoteLatest,
      query: {'inquiryId': inquiryId},
      parser: _mapParser,
    );
    if (data == null) return null;
    return Quote.fromJson(data);
  }

  // ==================== 订单 ====================

  /// 订单列表（分页）。
  Future<PagedData<Order>> pageOrders({
    String? role,
    String? status,
    String? keyword,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeOrders,
      query: _compact({
        'role': role,
        'status': status,
        'keyword': keyword,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取订单列表失败');
    return PagedData.parse<Order>(data, Order.fromJson);
  }

  /// 订单详情。
  Future<Order> orderDetail(int orderId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeOrderById(orderId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取订单详情失败');
    return Order.fromJson(data);
  }

  /// APP订单列表（分页，按角色）。
  Future<PagedData<Order>> appPageOrders({
    required String role,
    String? status,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appOrderList,
      query: _compact({
        'role': role,
        'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取订单列表失败');
    return PagedData.parse<Order>(data, Order.fromJson);
  }

  /// APP订单详情。
  Future<Order> appOrderDetail(int orderId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appOrderById(orderId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取订单详情失败');
    return Order.fromJson(data);
  }

  /// APP买方付款（paying → delivering）。
  Future<Map<String, dynamic>> appPayOrder(int orderId) async {
    final data = await _api.post<Map<String, dynamic>>(ApiEndpoints.appOrderPay(orderId), parser: _mapParser);
    if (data == null || data['qrCode'] is! String) throw ApiException('获取沙箱支付二维码失败');
    return data;
  }

  Future<bool> confirmSandboxPayment(int orderId) async {
    final data = await _api.post<Map<String, dynamic>>('${ApiEndpoints.appOrderPay(orderId)}/confirm', parser: _mapParser);
    return data?['paid'] == true;
  }

  /// APP买方确认收货（delivering → completed，托管释放+收益入账）。
  Future<void> appCompleteOrder(int orderId) async {
    await _api.post<void>(ApiEndpoints.appOrderComplete(orderId));
  }

  /// APP取消订单（仅 confirmed 可取消，双方签署完成前；买卖双方任一方可发起）。
  Future<void> appCancelOrder(int orderId) async {
    await _api.post<void>(ApiEndpoints.appOrderCancel(orderId));
  }

  // ==================== 合作记录 ====================

  /// 合作记录列表（分页）。
  Future<PagedData<Cooperation>> pageCooperations({
    String? source,
    int? workId,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeCooperationList,
      query: _compact({
        'source': source,
        'workId': workId,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取合作记录列表失败');
    return PagedData.parse<Cooperation>(data, Cooperation.fromJson);
  }

  /// 创建合作记录。
  Future<Cooperation> createCooperation(Cooperation cooperation) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.adminTradeCooperation,
      data: cooperation.toJson(),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('创建合作记录失败');
    return Cooperation.fromJson(data);
  }

  // ==================== 商务跟进 ====================

  /// 跟进记录列表（分页）。
  Future<PagedData<BusinessFollow>> pageFollowUps({
    int? partnerId,
    int? workId,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeFollowUps,
      query: _compact({
        'partnerId': partnerId,
        'workId': workId,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取跟进记录列表失败');
    return PagedData.parse<BusinessFollow>(data, BusinessFollow.fromJson);
  }

  /// 创建跟进记录。
  Future<BusinessFollow> createFollowUp(BusinessFollow follow) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.adminTradeFollowUps,
      data: follow.toJson(),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('创建跟进记录失败');
    return BusinessFollow.fromJson(data);
  }

  // ==================== 需求标签 ====================

  /// 需求标签列表（分页）。
  Future<PagedData<DemandTag>> pageDemandTags({
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminTradeDemandTags,
      query: _compact({
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取需求标签列表失败');
    return PagedData.parse<DemandTag>(data, DemandTag.fromJson);
  }

  // ==================== 财务域（收益 / 托管 / 发票） ====================

  /// 收益总览。
  Future<Map<String, dynamic>> incomeOverview() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceIncomeOverview,
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取收益总览失败');
    return data;
  }

  /// 收益明细列表（账单流水）。
  Future<PagedData<BillRecord>> pageBillRecords({
    String? billType,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceIncomeDetail,
      query: _compact({
        'billType': billType,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取收益明细失败');
    return PagedData.parse<BillRecord>(data, BillRecord.fromJson);
  }

  /// 资金托管列表。
  Future<PagedData<Escrow>> pageEscrows({
    required String role,
    String? status,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceEscrowList,
      query: _compact({
        'role': role,
        'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取托管列表失败');
    return PagedData.parse<Escrow>(data, Escrow.fromJson);
  }

  /// 资金托管列表 + 汇总（含 totalAmount/pendingAmount）。
  Future<EscrowSummary> fetchEscrowSummary({
    required String role,
    String? status,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceEscrowList,
      query: _compact({
        'role': role,
        'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取托管列表失败');
    final rows = (data['rows'] as List<dynamic>?)
            ?.map((e) => Escrow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return EscrowSummary(
      list: rows,
      totalAmount: (data['totalAmount'] as num?)?.toInt() ?? 0,
      pendingAmount: (data['pendingAmount'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// 托管详情。
  Future<Escrow> escrowDetail(int escrowId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceEscrowById(escrowId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取托管详情失败');
    return Escrow.fromJson(data);
  }

  /// 发票列表。
  Future<PagedData<Invoice>> pageInvoices({
    String? status,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceInvoiceList,
      query: _compact({
        'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取发票列表失败');
    return PagedData.parse<Invoice>(data, Invoice.fromJson);
  }

  /// 申请发票。
  Future<void> applyInvoice(Map<String, dynamic> body) async {
    await _api.post<void>(
      ApiEndpoints.appFinanceInvoiceApply,
      data: body,
    );
  }

  /// 可开票订单列表。
  Future<List<Map<String, dynamic>>> invoiceableOrders() async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.appFinanceInvoiceOrders,
      parser: (raw) => raw is List ? raw : [],
    );
    if (data == null) return [];
    return data.cast<Map<String, dynamic>>();
  }

  // ==================== 工具方法 ====================

  /// 移除 null 值，避免传给后端的查询参数带 null。
  static Map<String, dynamic> _compact(Map<String, dynamic> map) {
    return Map.fromEntries(
      map.entries.where((e) => e.value != null),
    );
  }

  /// 解包响应 data 为 Map。
  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw == null) return <String, dynamic>{};
    if (raw is Map<String, dynamic>) return raw;
    return <String, dynamic>{};
  }
}
