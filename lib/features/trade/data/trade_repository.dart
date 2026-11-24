import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'trade_models.dart';

/// C 交易域数据层（APP 专用接口 `/api/v1/trade/**`）。
///
/// 管理端接口 `/api/v1/admin/trade/**` 需要 trade:* 权限，用户 token 调过去必然 403，
/// 因此这里只保留 APP 侧可用的端点；历史上误接的管理端方法（交易作品/报价审核/订单/
/// 合作记录/跟进/托管）已随对应页面下线一并移除。
class TradeRepository {
  TradeRepository(this._api);

  final ApiClient _api;

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
      ApiEndpoints.tradeInquiryList,
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
      ApiEndpoints.tradeInquiryDetail(inquiryId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取询盘详情失败');
    return Inquiry.fromJson(data);
  }

  /// 创建询盘。
  Future<Inquiry> createInquiry(Inquiry inquiry) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.tradeInquiry,
      data: inquiry.toJson(),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('创建询盘失败');
    return Inquiry.fromJson(data);
  }

  /// 接受询盘。
  Future<void> acceptInquiry(int inquiryId) async {
    await _api.put<void>(
      ApiEndpoints.tradeInquiryAccept(inquiryId),
    );
  }

  /// 拒绝询盘。
  Future<void> rejectInquiry(int inquiryId) async {
    await _api.put<void>(
      ApiEndpoints.tradeInquiryReject(inquiryId),
    );
  }

  /// 关闭询盘。
  Future<void> closeInquiry(int inquiryId) async {
    await _api.put<void>(
      ApiEndpoints.tradeInquiryClose(inquiryId),
    );
  }

  /// 作品确权状态：是否已完成版权登记发证。
  ///
  /// true=有版权（发起询盘需选授权类型，成交后走合同签署）；
  /// false=无版权（不选授权类型，接受报价后跳过合同直达付款）。
  Future<bool> getCopyrightStatus(int workId) async {
    final copyrighted = await _api.get<bool>(
      ApiEndpoints.tradeInquiryCopyrightStatus,
      query: {'workId': workId},
      parser: (raw) => raw == true,
    );
    return copyrighted ?? false;
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

  /// 接受报价（APP端）。
  Future<Map<String, dynamic>> appAcceptQuote(int quoteId) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.appQuoteAccept(quoteId),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('接受报价失败');
    return data;
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

  // ==================== 订单（APP端） ====================

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

  /// 按询盘查关联订单（会话页「查看订单」跳转用）；无订单返回 null。
  Future<Map<String, dynamic>?> appOrderByInquiry(int inquiryId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appOrderByInquiry(inquiryId),
      parser: _mapParser,
    );
    return (data == null || data.isEmpty) ? null : data;
  }

  /// APP买方付款（paying → delivering）。
  /// [refresh] 为 true 时服务端换新商户单号重新预下单，用于收款码失效后换码。
  Future<Map<String, dynamic>> appPayOrder(int orderId, {bool refresh = false}) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.appOrderPay(orderId),
      query: <String, dynamic>{'refresh': refresh},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取沙箱支付二维码失败');
    // 旧码其实已被扫付时服务端直接结算并返回 paid，此时没有 qrCode
    if (data['paid'] == true) return data;
    if (data['qrCode'] is! String) throw ApiException('获取沙箱支付二维码失败');
    return data;
  }

  /// 查单确认沙箱支付，返回 {paid, closed?}；closed 为 true 表示支付宝侧该单已关闭、当前码失效。
  Future<Map<String, dynamic>> confirmSandboxPayment(int orderId) async {
    final data = await _api.post<Map<String, dynamic>>('${ApiEndpoints.appOrderPay(orderId)}/confirm', parser: _mapParser);
    return data ?? const <String, dynamic>{'paid': false};
  }

  /// APP取消订单（仅买方可发起，付款前有效：confirmed 或未付款的 paying）。
  Future<void> appCancelOrder(int orderId) async {
    await _api.post<void>(ApiEndpoints.appOrderCancel(orderId));
  }

  /// 测试直付：跳过支付宝沙箱，订单直接按已付款进入交割（与版权零元直付同性质）。
  Future<void> appDirectPayOrder(int orderId) async {
    await _api.post<void>(ApiEndpoints.appOrderDirectPay(orderId));
  }

  // ==================== 财务域（收益） ====================

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
