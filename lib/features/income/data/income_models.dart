/// 我的收益模块数据模型（独立于交易管理「作者收益」页）。
library;

/// 收益总览。
///
/// 金额字段单位：元（后端 overview 返回 BigDecimal 元）。
class IncomeOverview {
  const IncomeOverview({
    required this.totalIncome,
    required this.pendingSettleAmount,
    required this.availableAmount,
    this.withdrawnAmount = 0,
    this.frozenAmount = 0,
    this.monthIncome = 0,
    this.pendingSettleCount = 0,
  });

  final double totalIncome;
  final double pendingSettleAmount;
  final double availableAmount;
  final double withdrawnAmount;
  final double frozenAmount;
  final double monthIncome;
  final int pendingSettleCount;

  factory IncomeOverview.fromJson(Map<String, dynamic> json) {
    return IncomeOverview(
      totalIncome: _toYuan(json['totalIncome']),
      pendingSettleAmount: _toYuan(json['pendingSettleAmount']),
      availableAmount: _toYuan(json['availableAmount']),
      withdrawnAmount: _toYuan(json['withdrawnAmount']),
      frozenAmount: _toYuan(json['frozenAmount']),
      monthIncome: _toYuan(json['monthIncome']),
      pendingSettleCount: (json['pendingSettleCount'] as num?)?.toInt() ?? 0,
    );
  }

  static double _toYuan(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}

/// 收入/提现周期统计。金额单位：元。
class IncomePeriodStats {
  const IncomePeriodStats({
    required this.period,
    required this.incomeAmount,
    required this.withdrawAmount,
    this.periodStart,
    this.periodEnd,
  });

  final String period;
  final double incomeAmount;
  final double withdrawAmount;
  final String? periodStart;
  final String? periodEnd;

  factory IncomePeriodStats.fromJson(Map<String, dynamic> json) {
    return IncomePeriodStats(
      period: json['period']?.toString() ?? 'month',
      incomeAmount: IncomeOverview._toYuan(json['incomeAmount']),
      withdrawAmount: IncomeOverview._toYuan(json['withdrawAmount']),
      periodStart: json['periodStart']?.toString(),
      periodEnd: json['periodEnd']?.toString(),
    );
  }
}

/// 收益明细列表项（已入账账单）。金额单位：分。
class IncomeDetailItem {
  const IncomeDetailItem({
    this.billId,
    this.billNo,
    this.billType,
    this.incomeSource,
    this.amount,
    this.relatedType,
    this.relatedId,
    this.orderNo,
    this.workTitle,
    this.remark,
    this.createdAt,
  });

  final int? billId;
  final String? billNo;
  final String? billType;
  final String? incomeSource;
  final int? amount;
  final String? relatedType;
  final int? relatedId;
  final String? orderNo;
  final String? workTitle;
  final String? remark;
  final DateTime? createdAt;

  factory IncomeDetailItem.fromJson(Map<String, dynamic> json) {
    return IncomeDetailItem(
      billId: (json['billId'] as num?)?.toInt(),
      billNo: json['billNo'] as String?,
      billType: json['billType'] as String?,
      incomeSource: json['incomeSource'] as String?,
      amount: (json['amount'] as num?)?.toInt(),
      relatedType: json['relatedType'] as String?,
      relatedId: (json['relatedId'] as num?)?.toInt(),
      orderNo: json['orderNo'] as String?,
      workTitle: json['workTitle'] as String?,
      remark: json['remark'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  String get amountYuan {
    if (amount == null) return '-';
    final prefix = amount! >= 0 ? '+' : '';
    return '$prefix¥${(amount! / 100).toStringAsFixed(2)}';
  }

  String get sourceLabel => incomeSource ?? _fallbackSource(billType);

  String get orderSummary {
    final parts = <String>[
      if (orderNo != null && orderNo!.isNotEmpty) orderNo!,
      if (workTitle != null && workTitle!.isNotEmpty) workTitle!,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    if (relatedType == 'order' && relatedId != null) return '订单#$relatedId';
    return '无关联订单';
  }

  static String _fallbackSource(String? billType) {
    switch (billType) {
      case 'income':
        return '订单收入';
      case 'withdraw':
        return '提现支出';
      case 'freeze':
        return '资金冻结';
      case 'settle':
        return '分成结算';
      default:
        return billType ?? '未知';
    }
  }
}

/// 收益账单详情（含订单分成）。金额单位：分。
class IncomeBillDetail {
  const IncomeBillDetail({
    this.billId,
    this.billNo,
    this.billType,
    this.incomeSource,
    this.amount,
    this.balanceAfter,
    this.relatedType,
    this.relatedId,
    this.remark,
    this.createdAt,
    this.orderNo,
    this.orderStatus,
    this.workTitle,
    this.totalAmount,
    this.platformFee,
    this.splitRate,
    this.sellerAmount,
    this.payTime,
    this.completeTime,
  });

  final int? billId;
  final String? billNo;
  final String? billType;
  final String? incomeSource;
  final int? amount;
  final int? balanceAfter;
  final String? relatedType;
  final int? relatedId;
  final String? remark;
  final String? createdAt;
  final String? orderNo;
  final String? orderStatus;
  final String? workTitle;
  final int? totalAmount;
  final int? platformFee;
  final num? splitRate;
  final int? sellerAmount;
  final String? payTime;
  final String? completeTime;

  factory IncomeBillDetail.fromJson(Map<String, dynamic> json) {
    return IncomeBillDetail(
      billId: (json['billId'] as num?)?.toInt(),
      billNo: json['billNo'] as String?,
      billType: json['billType'] as String?,
      incomeSource: json['incomeSource'] as String?,
      amount: (json['amount'] as num?)?.toInt(),
      balanceAfter: (json['balanceAfter'] as num?)?.toInt(),
      relatedType: json['relatedType'] as String?,
      relatedId: (json['relatedId'] as num?)?.toInt(),
      remark: json['remark'] as String?,
      createdAt: json['createdAt']?.toString(),
      orderNo: json['orderNo'] as String?,
      orderStatus: json['orderStatus'] as String?,
      workTitle: json['workTitle'] as String?,
      totalAmount: (json['totalAmount'] as num?)?.toInt(),
      platformFee: (json['platformFee'] as num?)?.toInt(),
      splitRate: json['splitRate'] as num?,
      sellerAmount: (json['sellerAmount'] as num?)?.toInt(),
      payTime: json['payTime']?.toString(),
      completeTime: json['completeTime']?.toString(),
    );
  }

  String fenYuan(int? fen) {
    if (fen == null) return '-';
    return '¥${(fen / 100).toStringAsFixed(2)}';
  }

  String get splitRateLabel => formatSplitRate(splitRate);

  bool get hasOrder => orderNo != null && orderNo!.isNotEmpty;
}

/// 待结算单。金额单位：分。
class IncomeSettleItem {
  const IncomeSettleItem({
    this.settleId,
    this.settleNo,
    this.orderId,
    this.orderNo,
    this.workTitle,
    this.totalAmount,
    this.platformFee,
    this.splitRate,
    this.sellerAmount,
    this.status,
    this.disputeReason,
    this.billId,
    this.confirmTime,
    this.disputeTime,
    this.createdAt,
  });

  final int? settleId;
  final String? settleNo;
  final int? orderId;
  final String? orderNo;
  final String? workTitle;
  final int? sellerAmount;
  final int? totalAmount;
  final int? platformFee;
  final num? splitRate;
  final String? status;
  final String? disputeReason;
  final int? billId;
  final String? confirmTime;
  final String? disputeTime;
  final String? createdAt;

  factory IncomeSettleItem.fromJson(Map<String, dynamic> json) {
    return IncomeSettleItem(
      settleId: (json['settleId'] as num?)?.toInt(),
      settleNo: json['settleNo'] as String?,
      orderId: (json['orderId'] as num?)?.toInt(),
      orderNo: json['orderNo'] as String?,
      workTitle: json['workTitle'] as String?,
      totalAmount: (json['totalAmount'] as num?)?.toInt(),
      platformFee: (json['platformFee'] as num?)?.toInt(),
      splitRate: json['splitRate'] as num?,
      sellerAmount: (json['sellerAmount'] as num?)?.toInt(),
      status: json['status'] as String?,
      disputeReason: json['disputeReason'] as String?,
      billId: (json['billId'] as num?)?.toInt(),
      confirmTime: json['confirmTime'] as String?,
      disputeTime: json['disputeTime'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }

  String get sellerAmountYuan {
    if (sellerAmount == null) return '-';
    return '¥${(sellerAmount! / 100).toStringAsFixed(2)}';
  }

  String fenYuan(int? fen) {
    if (fen == null) return '-';
    return '¥${(fen / 100).toStringAsFixed(2)}';
  }

  String get splitRateLabel => formatSplitRate(splitRate);

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '待确认';
      case 'confirmed':
        return '已入账';
      case 'disputed':
        return '有异议';
      default:
        return status ?? '未知';
    }
  }

  bool get canConfirm => status == 'pending' || status == 'disputed';
  bool get canDispute => status == 'pending';
}

/// 提现记录。金额单位：分。
class WithdrawRecord {
  const WithdrawRecord({
    this.withdrawId,
    this.withdrawNo,
    this.amount,
    this.fee,
    this.actualAmount,
    this.withdrawType,
    this.accountName,
    this.accountNo,
    this.bankName,
    this.status,
    this.reviewOpinion,
    this.reviewTime,
    this.payTime,
    this.createdAt,
  });

  final int? withdrawId;
  final String? withdrawNo;
  final int? amount;
  final int? fee;
  final int? actualAmount;
  final String? withdrawType;
  final String? accountName;
  final String? accountNo;
  final String? bankName;
  final String? status;
  final String? reviewOpinion;
  final String? reviewTime;
  final String? payTime;
  final String? createdAt;

  factory WithdrawRecord.fromJson(Map<String, dynamic> json) {
    return WithdrawRecord(
      withdrawId: (json['withdrawId'] as num?)?.toInt(),
      withdrawNo: json['withdrawNo'] as String?,
      amount: (json['amount'] as num?)?.toInt(),
      fee: (json['fee'] as num?)?.toInt(),
      actualAmount: (json['actualAmount'] as num?)?.toInt(),
      withdrawType: json['withdrawType'] as String?,
      accountName: json['accountName'] as String?,
      accountNo: json['accountNo'] as String?,
      bankName: json['bankName'] as String?,
      status: json['status'] as String?,
      reviewOpinion: json['reviewOpinion'] as String?,
      reviewTime: json['reviewTime'] as String?,
      payTime: json['payTime'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }

  String get amountYuan {
    if (amount == null) return '-';
    return '¥${(amount! / 100).toStringAsFixed(2)}';
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '待审核';
      case 'approved':
        return '已通过';
      case 'rejected':
        return '已驳回';
      case 'frozen':
        return '已冻结';
      case 'paid':
        return '已打款';
      default:
        return status ?? '未知';
    }
  }

  String get typeLabel {
    switch (withdrawType) {
      case 'bank':
        return '银行卡';
      case 'alipay':
        return '支付宝';
      case 'wechat':
        return '微信';
      default:
        return withdrawType ?? '-';
    }
  }

  bool get isFailed => status == 'rejected';
}

/// 结算抽成比例展示：0.05 → 5%。
String formatSplitRate(num? rate) {
  if (rate == null) return '-';
  final pct = rate.abs() <= 1 ? rate * 100 : rate;
  if (pct == pct.roundToDouble()) {
    return '${pct.toStringAsFixed(0)}%';
  }
  return '${pct.toStringAsFixed(2)}%';
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
