import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'recharge_models.dart';
import 'welfare_models.dart';

/// 福利中心仓库（App 端 E 模块）。
class WelfareRepository {
  WelfareRepository(this._api);

  final ApiClient _api;

  /// 任务列表 + 我的进度。
  Future<List<WelfareTask>> tasks(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/welfare/tasks',
      query: {'userId': userId},
      parser: _map,
    );
    return _parseList(data, 'tasks', WelfareTask.fromJson);
  }

  /// 积分余额。
  Future<PointsBalance> pointsBalance(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/welfare/points/balance',
      query: {'userId': userId},
      parser: _map,
    );
    return PointsBalance.fromJson(data ?? const {});
  }

  /// 积分明细。
  Future<List<PointsRecord>> pointsRecords(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/welfare/points/records',
      query: {'userId': userId},
      parser: _map,
    );
    return _parseList(data, 'records', PointsRecord.fromJson);
  }

  /// 广告任务列表。
  Future<List<AdTask>> adList(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/welfare/ad/list',
      query: {'userId': userId},
      parser: _map,
    );
    return _parseList(data, 'ads', AdTask.fromJson);
  }

  /// 积分兑换 AI 次数记录。
  Future<List<ExchangeRecord>> exchangeRecords(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/welfare/ai/quota/exchange-records',
      query: {'userId': userId},
      parser: _map,
    );
    return _parseList(data, 'records', ExchangeRecord.fromJson);
  }

  /// 充值页配置（换算比例 / 档位 / 支付渠道 / 当前余额）。
  Future<RechargeConfig> rechargeConfig(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/welfare/recharge/config',
      query: {'userId': userId},
      parser: _map,
    );
    return RechargeConfig.fromJson(data ?? const {});
  }

  /// 创建充值订单（待支付）。
  Future<RechargePayResult> createRechargeOrder({
    required int userId,
    required int yuan,
    required String channel,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/welfare/recharge/order',
      data: <String, dynamic>{
        'userId': userId,
        'yuan': yuan,
        'channel': channel,
      },
      parser: _map,
    );
    return RechargePayResult.fromJson(data ?? const {});
  }

  /// 模拟支付成功（真实微信/支付宝对接由支付组替换此调用）。
  Future<RechargePayResult> payRecharge({
    required int userId,
    required String orderNo,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/welfare/recharge/mock-pay',
      data: <String, dynamic>{'userId': userId, 'orderNo': orderNo},
      parser: _map,
    );
    return RechargePayResult.fromJson(data ?? const {});
  }

  /// 充值记录（按时间倒序）。
  Future<List<RechargeRecord>> rechargeRecords(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/welfare/recharge/orders',
      query: {'userId': userId, 'limit': 20},
      parser: _map,
    );
    return _parseList(data, 'orders', RechargeRecord.fromJson);
  }

  /// 领取任务奖励（幂等；返回领取后积分余额）。
  Future<int> claimTask({
    required int userId,
    required String taskCode,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/welfare/task/claim',
      data: <String, dynamic>{'taskCode': taskCode, 'userId': userId},
      parser: _map,
    );
    return (data?['balance'] as num?)?.toInt() ?? 0;
  }

  /// 广告观看奖励（幂等；返回领取后积分余额与奖励积分）。
  Future<({int balance, int rewardPoints})> adReward({
    required int userId,
    required int adId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/ad/reward',
      data: <String, dynamic>{'adId': adId, 'userId': userId},
      parser: _map,
    );
    return (
      balance: (data?['balance'] as num?)?.toInt() ?? 0,
      rewardPoints: (data?['rewardPoints'] as num?)?.toInt() ?? 0,
    );
  }

  /// 上报任务行为进度（App 完成真实行为后调用，如阅读/上传/登录）。
  /// 返回 {progress, targetCount, isCompleted}；任务不存在/未启用时抛异常由调用方静默。
  Future<({int progress, int targetCount, int isCompleted})> reportTaskProgress({
    required int userId,
    required String taskCode,
    int increment = 1,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/welfare/task/progress',
      data: <String, dynamic>{
        'taskCode': taskCode,
        'userId': userId,
        'increment': increment,
      },
      parser: _map,
    );
    return (
      progress: (data?['progress'] as num?)?.toInt() ?? 0,
      targetCount: (data?['targetCount'] as num?)?.toInt() ?? 1,
      isCompleted: (data?['isCompleted'] as num?)?.toInt() ?? 0,
    );
  }

  static List<T> _parseList<T>(
    Map<String, dynamic>? data,
    String key,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (data == null) return const [];
    final raw = data[key];
    if (raw is! List) return const [];
    return raw
        .map((e) => parser(e is Map ? Map<String, dynamic>.from(e) : const {}))
        .toList();
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((key, value) => MapEntry('$key', value));
    throw ApiException('服务暂时不可用，请稍后再试');
  }
}
