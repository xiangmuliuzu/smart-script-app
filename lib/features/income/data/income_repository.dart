import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'income_models.dart';

/// 我的收益数据仓库。
class IncomeRepository {
  IncomeRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _compact(Map<String, dynamic> query) {
    query.removeWhere((_, v) => v == null || (v is String && v.isEmpty));
    return query;
  }

  Future<IncomeOverview> overview() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceIncomeOverview,
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取收益总览失败');
    return IncomeOverview.fromJson(data);
  }

  /// 收入/提现统计。period: week / month / year
  Future<IncomePeriodStats> stats({required String period}) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceIncomeStats,
      query: {'period': period},
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取收支统计失败');
    return IncomePeriodStats.fromJson(data);
  }

  Future<PagedData<IncomeDetailItem>> pageDetails({
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
    return PagedData.parse<IncomeDetailItem>(data, IncomeDetailItem.fromJson);
  }

  Future<IncomeBillDetail> billDetail(int billId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceIncomeBillDetail(billId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取账单详情失败');
    return IncomeBillDetail.fromJson(data);
  }

  Future<PagedData<IncomeSettleItem>> pageSettles({
    String? status,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceSettleList,
      query: _compact({
        'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取待结算列表失败');
    return PagedData.parse<IncomeSettleItem>(data, IncomeSettleItem.fromJson);
  }

  Future<IncomeSettleItem> settleDetail(int settleId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceSettleById(settleId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取待结算详情失败');
    return IncomeSettleItem.fromJson(data);
  }

  Future<void> confirmSettle(int settleId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.appFinanceSettleConfirm(settleId),
      parser: _mapParser,
    );
  }

  Future<void> disputeSettle(int settleId, String reason) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.appFinanceSettleDispute(settleId),
      data: {'reason': reason},
      parser: _mapParser,
    );
  }

  Future<Map<String, dynamic>> applyWithdraw({
    required double amount,
    required String withdrawType,
    required String accountName,
    required String accountNo,
    String? bankName,
    String? clientToken,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.appFinanceWithdrawApply,
      data: _compact({
        'amount': amount,
        'withdrawType': withdrawType,
        'accountName': accountName,
        'accountNo': accountNo,
        'bankName': bankName,
        'clientToken': clientToken,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('提现申请失败');
    return data;
  }

  Future<PagedData<WithdrawRecord>> pageWithdraws({
    String? status,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appFinanceWithdrawList,
      query: _compact({
        'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取提现记录失败');
    return PagedData.parse<WithdrawRecord>(data, WithdrawRecord.fromJson);
  }
}
