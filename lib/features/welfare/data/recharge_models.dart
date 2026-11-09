/// 积分充值数据模型（App 端 E 模块）。
///
/// 接口口径（后端 smartscript-review，App 用户侧，统一信封 {code,msg,data}）：
///   GET  /api/v1/welfare/recharge/config?userId=  → 换算比例 / 金额范围 / 固定档位 / 支付渠道 / 当前余额
///   POST /api/v1/welfare/recharge/order           → 创建充值订单（待支付）
///   POST /api/v1/welfare/recharge/mock-pay        → 模拟支付成功（积分到账，幂等）
///   GET  /api/v1/welfare/recharge/orders?userId=  → 充值记录
///
/// 真实微信/支付宝对接由支付组接入，页面结构保持不变。
library;

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _text(dynamic value) => value == null ? '' : value.toString();

/// 固定充值档位（元 → 积分）。
class RechargePlan {
  const RechargePlan({
    required this.yuan,
    this.amountFen = 0,
    this.points = 0,
  });

  final int yuan;
  final int amountFen;
  final int points;

  factory RechargePlan.fromJson(Map<String, dynamic> json) => RechargePlan(
        yuan: _int(json['yuan']),
        amountFen: _int(json['amountFen']),
        points: _int(json['points']),
      );
}

/// 支付渠道（微信 / 支付宝）。
class RechargeChannel {
  const RechargeChannel({
    required this.code,
    this.name = '',
    this.enabled = true,
  });

  final String code;
  final String name;
  final bool enabled;

  factory RechargeChannel.fromJson(Map<String, dynamic> json) => RechargeChannel(
        code: _text(json['code']),
        name: _text(json['name']),
        enabled: json['enabled'] == true || json['enabled'] == 1,
      );
}

/// 充值页配置。
class RechargeConfig {
  const RechargeConfig({
    this.pointsPerYuan = 100,
    this.minYuan = 1,
    this.maxYuan = 100000,
    this.balance = 0,
    this.plans = const [],
    this.channels = const [],
  });

  final int pointsPerYuan;
  final int minYuan;
  final int maxYuan;
  final int balance;
  final List<RechargePlan> plans;
  final List<RechargeChannel> channels;

  /// 金额换算积分（不足 1 元的金额按 0 处理）。
  int pointsOf(int yuan) => yuan <= 0 ? 0 : yuan * pointsPerYuan;

  factory RechargeConfig.fromJson(Map<String, dynamic> json) {
    final rawPlans = json['plans'];
    final rawChannels = json['channels'];
    return RechargeConfig(
      pointsPerYuan: _int(json['pointsPerYuan']) <= 0 ? 100 : _int(json['pointsPerYuan']),
      minYuan: _int(json['minYuan']) <= 0 ? 1 : _int(json['minYuan']),
      maxYuan: _int(json['maxYuan']) <= 0 ? 100000 : _int(json['maxYuan']),
      balance: _int(json['balance']),
      plans: rawPlans is List
          ? rawPlans
              .map((e) => RechargePlan.fromJson(
                  e is Map ? Map<String, dynamic>.from(e) : const {}))
              .toList()
          : const [],
      channels: rawChannels is List
          ? rawChannels
              .map((e) => RechargeChannel.fromJson(
                  e is Map ? Map<String, dynamic>.from(e) : const {}))
              .toList()
          : const [],
    );
  }
}

/// 下单 / 模拟支付结果。
class RechargePayResult {
  const RechargePayResult({
    this.orderNo = '',
    this.status = '',
    this.points = 0,
    this.amountFen = 0,
    this.balance = 0,
    this.alreadyPaid = false,
  });

  final String orderNo;
  final String status;
  final int points;
  final int amountFen;
  final int balance;
  final bool alreadyPaid;

  factory RechargePayResult.fromJson(Map<String, dynamic> json) =>
      RechargePayResult(
        orderNo: _text(json['orderNo']),
        status: _text(json['status']),
        points: _int(json['points']),
        amountFen: _int(json['amountFen']),
        balance: _int(json['balance']),
        alreadyPaid: json['alreadyPaid'] == true || json['alreadyPaid'] == 1,
      );
}

/// 充值记录条目。
class RechargeRecord {
  const RechargeRecord({
    this.orderNo = '',
    this.amountFen = 0,
    this.points = 0,
    this.channel = '',
    this.status = '',
    this.payTime,
    this.createTime,
  });

  final String orderNo;
  final int amountFen;
  final int points;
  final String channel;
  final String status;
  final String? payTime;
  final String? createTime;

  String get channelLabel => channel == 'ALIPAY' ? '支付宝' : '微信支付';

  String get statusLabel {
    switch (status) {
      case 'PAID':
        return '已到账';
      case 'CANCELLED':
        return '已取消';
      default:
        return '待支付';
    }
  }

  factory RechargeRecord.fromJson(Map<String, dynamic> json) => RechargeRecord(
        orderNo: _text(json['orderNo']),
        amountFen: _int(json['amountFen']),
        points: _int(json['points']),
        channel: _text(json['channel']),
        status: _text(json['status']),
        payTime: json['payTime']?.toString(),
        createTime: json['createTime']?.toString(),
      );
}
