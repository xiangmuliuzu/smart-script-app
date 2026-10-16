/// C 交易域数据模型（询盘/报价/订单/合作记录/需求标签/商务跟进）
/// 
/// 字段对齐后端 domain：SysInquiry / SysQuote / SysOrder / SysOfflineCooperation /
/// SysDemandTag / SysBusinessFollow。
/// 金额单位：分（后端 BigDecimal 序列化后为 double，前端展示时 /100）。

// ==================== 枚举常量 ====================

/// 询盘状态（对齐后端 TradeInquiryService：accepted 已于 2026-09-29 并入 quoted）
class InquiryStatus {
  static const String pending = 'pending';           // 待处理
  static const String quoted = 'quoted';             // 议价中（有报价在谈）
  static const String rejected = 'rejected';         // 已拒绝
  static const String deal = 'deal';                 // 已达成（一方接受报价后，同步生成订单）
  static const String closed = 'closed';             // 已关闭

  static String label(String? status) {
    switch (status) {
      case pending: return '待处理';
      case quoted: return '议价中';
      case rejected: return '已拒绝';
      case deal: return '已达成';
      case closed: return '已关闭';
      default: return status ?? '未知';
    }
  }
}

/// 报价状态
class QuoteStatus {
  static const String pending = 'pending';               // 待回复
  static const String pendingSeller = 'pending_seller';  // 待卖方确认
  static const String accepted = 'accepted';             // 已接受
  static const String rejected = 'rejected';             // 已拒绝
  static const String expired = 'expired';               // 已过期

  static String label(String? status) {
    switch (status) {
      case pending: return '待回复';
      case pendingSeller: return '待卖方确认';
      case accepted: return '已接受';
      case rejected: return '已拒绝';
      case expired: return '已过期';
      default: return status ?? '未知';
    }
  }
}

/// 订单状态（对齐后端状态机：confirmed → escrow_pending → delivering → completed）
class OrderStatus {
  static const String confirmed = 'confirmed';            // 已确认（待买方付款）
  static const String escrowPending = 'escrow_pending';   // 已托管（资金入托管，待卖方交割）
  static const String delivering = 'delivering';          // 交割中
  static const String completed = 'completed';            // 已完成（托管释放，收益入账）
  static const String cancelled = 'cancelled';            // 已取消
  static const String refunded = 'refunded';              // 已退款

  static String label(String? status) {
    switch (status) {
      case confirmed: return '已确认';
      case escrowPending: return '已托管';
      case delivering: return '交割中';
      case completed: return '已完成';
      case cancelled: return '已取消';
      case refunded: return '已退款';
      default: return status ?? '未知';
    }
  }
}

/// 授权类型
class LicenseType {
  static const String exclusive = 'exclusive';           // 独家授权
  static const String nonExclusive = 'non_exclusive';    // 非独家授权
  static const String adaptation = 'adaptation';         // 改编授权

  static String label(String? type) {
    switch (type) {
      case exclusive: return '独家授权';
      case nonExclusive: return '非独家授权';
      case adaptation: return '改编授权';
      default: return type ?? '未知';
    }
  }
}

/// 报价方
class QuoteRole {
  static const String buyer = 'buyer';     // 买方出价
  static const String seller = 'seller';   // 卖方出价

  static String label(String? role) {
    switch (role) {
      case buyer: return '买方出价';
      case seller: return '卖方出价';
      default: return role ?? '未知';
    }
  }
}

/// 跟进方式
class FollowUpMethod {
  static const String phone = 'phone';
  static const String wechat = 'wechat';
  static const String email = 'email';
  static const String meeting = 'meeting';
  static const String other = 'other';

  static String label(String? method) {
    switch (method) {
      case phone: return '电话';
      case wechat: return '微信';
      case email: return '邮件';
      case meeting: return '面谈';
      case other: return '其他';
      default: return method ?? '未知';
    }
  }
}

/// 合作记录来源（线上合作意向 / 线下谈判）
class CooperationSource {
  static const String online = 'online';
  static const String offline = 'offline';

  static String label(String? source) {
    switch (source) {
      case online: return '线上合作';
      case offline: return '线下谈判';
      default: return source ?? '未知';
    }
  }
}

// ==================== 数据模型 ====================

/// 询盘
class Inquiry {
  final int? inquiryId;
  final String? inquiryNo;
  final int? workId;
  final int? buyerId;
  final int? sellerId;
  final String? licenseType;
  final String? intendedUse;
  final int? budget;        // 分
  final String? message;
  final String? status;
  final DateTime? expireAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // Transient
  final String? workTitle;
  final String? buyerName;
  final String? sellerName;

  const Inquiry({
    this.inquiryId,
    this.inquiryNo,
    this.workId,
    this.buyerId,
    this.sellerId,
    this.licenseType,
    this.intendedUse,
    this.budget,
    this.message,
    this.status,
    this.expireAt,
    this.createdAt,
    this.updatedAt,
    this.workTitle,
    this.buyerName,
    this.sellerName,
  });

  factory Inquiry.fromJson(Map<String, dynamic> json) {
    return Inquiry(
      inquiryId: json['inquiryId'] as int?,
      inquiryNo: json['inquiryNo'] as String?,
      workId: json['workId'] as int?,
      buyerId: json['buyerId'] as int?,
      sellerId: json['sellerId'] as int?,
      licenseType: json['licenseType'] as String?,
      intendedUse: json['intendedUse'] as String?,
      budget: (json['budget'] as num?)?.toInt(),
      message: json['message'] as String?,
      status: json['status'] as String?,
      expireAt: _parseDateTime(json['expireAt']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      workTitle: json['workTitle'] as String?,
      buyerName: json['buyerName'] as String?,
      sellerName: json['sellerName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (inquiryId != null) 'inquiryId': inquiryId,
      if (inquiryNo != null) 'inquiryNo': inquiryNo,
      if (workId != null) 'workId': workId,
      if (buyerId != null) 'buyerId': buyerId,
      if (sellerId != null) 'sellerId': sellerId,
      if (licenseType != null) 'licenseType': licenseType,
      if (intendedUse != null) 'intendedUse': intendedUse,
      if (budget != null) 'budget': budget,
      if (message != null) 'message': message,
      if (status != null) 'status': status,
    };
  }

  /// 金额展示（分转元）
  String get budgetYuan {
    if (budget == null) return '-';
    return '¥${(budget! / 100).toStringAsFixed(2)}';
  }
}

/// 报价/议价
class Quote {
  final int? quoteId;
  final int? inquiryId;
  final int? workId;
  final String? role;         // buyer / seller (quoterRole)
  final int? amount;          // 分 (price)
  final String? licenseType;
  final int? validDays;       // 有效天数
  final String? message;      // description
  final String? status;
  final DateTime? expireAt;
  final DateTime? createdAt;
  // Transient
  final String? inquiryNo;
  final String? workTitle;
  final String? operatorName;

  const Quote({
    this.quoteId,
    this.inquiryId,
    this.workId,
    this.role,
    this.amount,
    this.licenseType,
    this.validDays,
    this.message,
    this.status,
    this.expireAt,
    this.createdAt,
    this.inquiryNo,
    this.workTitle,
    this.operatorName,
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      quoteId: json['quoteId'] as int?,
      inquiryId: json['inquiryId'] as int?,
      workId: json['workId'] as int?,
      role: (json['quoterRole'] ?? json['role']) as String?,
      amount: ((json['price'] ?? json['amount']) as num?)?.toInt(),
      licenseType: json['licenseType'] as String?,
      validDays: json['validDays'] as int?,
      message: (json['description'] ?? json['message']) as String?,
      status: json['status'] as String?,
      expireAt: _parseDateTime(json['expireAt']),
      createdAt: _parseDateTime(json['createdAt']),
      inquiryNo: json['inquiryNo'] as String?,
      workTitle: json['workTitle'] as String?,
      operatorName: (json['quoterName'] ?? json['operatorName']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (quoteId != null) 'quoteId': quoteId,
      if (inquiryId != null) 'inquiryId': inquiryId,
      if (workId != null) 'workId': workId,
      if (role != null) 'quoterRole': role,
      if (amount != null) 'price': amount,
      if (licenseType != null) 'licenseType': licenseType,
      if (validDays != null) 'validDays': validDays,
      if (message != null) 'description': message,
      if (status != null) 'status': status,
    };
  }

  String get amountYuan {
    if (amount == null) return '-';
    return '¥${(amount! / 100).toStringAsFixed(2)}';
  }
}

/// 订单
class Order {
  final int? orderId;
  final String? orderNo;
  final int? inquiryId;
  final int? quoteId;
  final int? workId;
  final int? buyerId;
  final int? sellerId;
  final int? amount;          // 分
  final String? licenseType;
  final String? status;
  final String? cancelReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // Transient
  final String? workTitle;
  final String? buyerName;
  final String? sellerName;

  const Order({
    this.orderId,
    this.orderNo,
    this.inquiryId,
    this.quoteId,
    this.workId,
    this.buyerId,
    this.sellerId,
    this.amount,
    this.licenseType,
    this.status,
    this.cancelReason,
    this.createdAt,
    this.updatedAt,
    this.workTitle,
    this.buyerName,
    this.sellerName,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      orderId: json['orderId'] as int?,
      orderNo: json['orderNo'] as String?,
      inquiryId: json['inquiryId'] as int?,
      quoteId: json['quoteId'] as int?,
      workId: json['workId'] as int?,
      buyerId: json['buyerId'] as int?,
      sellerId: json['sellerId'] as int?,
      amount: (json['amount'] as num?)?.toInt(),
      licenseType: json['licenseType'] as String?,
      status: json['status'] as String?,
      cancelReason: json['cancelReason'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      workTitle: json['workTitle'] as String?,
      buyerName: json['buyerName'] as String?,
      sellerName: json['sellerName'] as String?,
    );
  }

  String get amountYuan {
    if (amount == null) return '-';
    return '¥${(amount! / 100).toStringAsFixed(2)}';
  }
}

/// 合作记录（线上合作意向 / 线下谈判）
class Cooperation {
  final int? cooperationId;
  final String? source;       // online / offline
  final int? workId;
  final int? partnerId;
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;
  final DateTime? meetingTime;
  final String? meetingPlace;
  final String? content;
  final String? remark;
  final DateTime? createdAt;
  // Transient
  final String? workTitle;
  final String? partnerName;

  const Cooperation({
    this.cooperationId,
    this.source,
    this.workId,
    this.partnerId,
    this.contactName,
    this.contactPhone,
    this.contactEmail,
    this.meetingTime,
    this.meetingPlace,
    this.content,
    this.remark,
    this.createdAt,
    this.workTitle,
    this.partnerName,
  });

  factory Cooperation.fromJson(Map<String, dynamic> json) {
    return Cooperation(
      cooperationId: json['cooperationId'] as int?,
      source: json['source'] as String?,
      workId: json['workId'] as int?,
      partnerId: json['partnerId'] as int?,
      contactName: json['contactName'] as String?,
      contactPhone: json['contactPhone'] as String?,
      contactEmail: json['contactEmail'] as String?,
      meetingTime: _parseDateTime(json['meetingTime']),
      meetingPlace: json['meetingPlace'] as String?,
      content: json['content'] as String?,
      remark: json['remark'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
      workTitle: json['workTitle'] as String?,
      partnerName: json['partnerName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (cooperationId != null) 'cooperationId': cooperationId,
      if (source != null) 'source': source,
      if (workId != null) 'workId': workId,
      if (partnerId != null) 'partnerId': partnerId,
      if (contactName != null) 'contactName': contactName,
      if (contactPhone != null) 'contactPhone': contactPhone,
      if (contactEmail != null) 'contactEmail': contactEmail,
      if (meetingTime != null) 'meetingTime': meetingTime!.toIso8601String(),
      if (meetingPlace != null) 'meetingPlace': meetingPlace,
      if (content != null) 'content': content,
      if (remark != null) 'remark': remark,
    };
  }
}

/// 需求标签
class DemandTag {
  final int? tagId;
  final String? tagName;
  final String? tagCode;
  final int? sort;
  final DateTime? createdAt;

  const DemandTag({
    this.tagId,
    this.tagName,
    this.tagCode,
    this.sort,
    this.createdAt,
  });

  factory DemandTag.fromJson(Map<String, dynamic> json) {
    return DemandTag(
      tagId: json['tagId'] as int?,
      tagName: json['tagName'] as String?,
      tagCode: json['tagCode'] as String?,
      sort: json['sort'] as int?,
      createdAt: _parseDateTime(json['createdAt']),
    );
  }
}

/// 商务跟进记录
class BusinessFollow {
  final int? followId;
  final int? partnerId;
  final int? workId;
  final String? followMethod;   // phone/wechat/email/meeting/other
  final String? content;
  final String? result;
  final String? nextPlan;
  final DateTime? followTime;
  final DateTime? createdAt;
  // Transient
  final String? partnerName;
  final String? workTitle;
  final String? creatorName;

  const BusinessFollow({
    this.followId,
    this.partnerId,
    this.workId,
    this.followMethod,
    this.content,
    this.result,
    this.nextPlan,
    this.followTime,
    this.createdAt,
    this.partnerName,
    this.workTitle,
    this.creatorName,
  });

  factory BusinessFollow.fromJson(Map<String, dynamic> json) {
    return BusinessFollow(
      followId: json['followId'] as int?,
      partnerId: json['partnerId'] as int?,
      workId: json['workId'] as int?,
      followMethod: json['followMethod'] as String?,
      content: json['content'] as String?,
      result: json['result'] as String?,
      nextPlan: json['nextPlan'] as String?,
      followTime: _parseDateTime(json['followTime']),
      createdAt: _parseDateTime(json['createdAt']),
      partnerName: json['partnerName'] as String?,
      workTitle: json['workTitle'] as String?,
      creatorName: json['creatorName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (followId != null) 'followId': followId,
      if (partnerId != null) 'partnerId': partnerId,
      if (workId != null) 'workId': workId,
      if (followMethod != null) 'followMethod': followMethod,
      if (content != null) 'content': content,
      if (result != null) 'result': result,
      if (nextPlan != null) 'nextPlan': nextPlan,
      if (followTime != null) 'followTime': followTime!.toIso8601String(),
    };
  }
}

/// 交易作品（sys_work 的交易视图）
class TradeWork {
  final int? workId;
  final String? title;
  final String? coverUrl;
  final String? workType;
  final String? authorName;
  final bool? tradeEnabled;
  final String? licenseType;
  final int? price;           // 分
  final bool? negotiable;
  final String? status;
  final DateTime? createdAt;

  const TradeWork({
    this.workId,
    this.title,
    this.coverUrl,
    this.workType,
    this.authorName,
    this.tradeEnabled,
    this.licenseType,
    this.price,
    this.negotiable,
    this.status,
    this.createdAt,
  });

  factory TradeWork.fromJson(Map<String, dynamic> json) {
    return TradeWork(
      workId: json['workId'] as int?,
      title: json['title'] as String?,
      coverUrl: json['coverUrl'] as String?,
      workType: json['workType'] as String?,
      authorName: json['authorName'] as String?,
      tradeEnabled: json['tradeEnabled'] as bool?,
      licenseType: json['licenseType'] as String?,
      price: (json['price'] as num?)?.toInt(),
      negotiable: json['negotiable'] as bool?,
      status: json['status'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  String get priceYuan {
    if (price == null) return '-';
    return '¥${(price! / 100).toStringAsFixed(2)}';
  }
}

// ==================== 财务域模型 ====================

/// 托管状态
class EscrowStatus {
  static const String pending = 'pending';
  static const String escrowed = 'escrowed';
  static const String released = 'released';
  static const String refunded = 'refunded';

  static String label(String? status) {
    switch (status) {
      case pending: return '待托管';
      case escrowed: return '托管中';
      case released: return '已释放';
      case refunded: return '已退款';
      default: return status ?? '未知';
    }
  }
}

/// 发票状态
class InvoiceStatus {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const String issued = 'issued';

  static String label(String? status) {
    switch (status) {
      case pending: return '待审核';
      case approved: return '已审核';
      case rejected: return '已拒绝';
      case issued: return '已开具';
      default: return status ?? '未知';
    }
  }
}

/// 资金托管记录
class Escrow {
  final int? escrowId;
  final String? escrowNo;
  final int? orderId;
  final int? amount; // 分
  final String? status;
  final DateTime? paidAt;
  final String? payChannel;
  final DateTime? releaseTime;
  final String? releaseReason;
  final int? refundAmount; // 分
  final DateTime? refundedAt;
  final DateTime? createdAt;
  final String? orderNo;
  final String? workTitle;
  final int? buyerId;
  final int? sellerId;
  final String? buyerName;
  final String? sellerName;

  Escrow({
    this.escrowId, this.escrowNo, this.orderId, this.amount, this.status,
    this.paidAt, this.payChannel, this.releaseTime, this.releaseReason,
    this.refundAmount, this.refundedAt, this.createdAt,
    this.orderNo, this.workTitle, this.buyerId, this.sellerId,
    this.buyerName, this.sellerName,
  });

  factory Escrow.fromJson(Map<String, dynamic> json) {
    return Escrow(
      escrowId: json['escrowId'] as int?,
      escrowNo: json['escrowNo'] as String?,
      orderId: json['orderId'] as int?,
      amount: (json['amount'] as num?)?.toInt(),
      status: json['status'] as String?,
      paidAt: _parseDateTime(json['paidAt']),
      payChannel: json['payChannel'] as String?,
      releaseTime: _parseDateTime(json['releaseTime']),
      releaseReason: json['releaseReason'] as String?,
      refundAmount: (json['refundAmount'] as num?)?.toInt(),
      refundedAt: _parseDateTime(json['refundedAt']),
      createdAt: _parseDateTime(json['createdAt']),
      orderNo: json['orderNo'] as String?,
      workTitle: json['workTitle'] as String?,
      buyerId: json['buyerId'] as int?,
      sellerId: json['sellerId'] as int?,
      buyerName: json['buyerName'] as String?,
      sellerName: json['sellerName'] as String?,
    );
  }

  String get amountYuan => amount != null ? '¥${(amount! / 100).toStringAsFixed(2)}' : '-';
}

/// 发票
class Invoice {
  final int? invoiceId;
  final String? invoiceNo;
  final int? orderId;
  final int? applicantId;
  final String? invoiceType;
  final String? email;
  final String? title;
  final String? taxNo;
  final int? amount; // 分
  final String? invoiceUrl;
  final String? status;
  final String? rejectReason;
  final DateTime? invoiceTime;
  final DateTime? createdAt;
  final String? orderNo;
  final String? workTitle;

  Invoice({
    this.invoiceId, this.invoiceNo, this.orderId, this.applicantId,
    this.invoiceType, this.email, this.title, this.taxNo, this.amount,
    this.invoiceUrl, this.status, this.rejectReason, this.invoiceTime,
    this.createdAt, this.orderNo, this.workTitle,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      invoiceId: json['invoiceId'] as int?,
      invoiceNo: json['invoiceNo'] as String?,
      orderId: json['orderId'] as int?,
      applicantId: json['applicantId'] as int?,
      invoiceType: json['invoiceType'] as String?,
      email: json['email'] as String?,
      title: json['title'] as String?,
      taxNo: json['taxNo'] as String?,
      amount: (json['amount'] as num?)?.toInt(),
      invoiceUrl: json['invoiceUrl'] as String?,
      status: json['status'] as String?,
      rejectReason: json['rejectReason'] as String?,
      invoiceTime: _parseDateTime(json['invoiceTime']),
      createdAt: _parseDateTime(json['createdAt']),
      orderNo: json['orderNo'] as String?,
      workTitle: json['workTitle'] as String?,
    );
  }

  String get amountYuan => amount != null ? '¥${(amount! / 100).toStringAsFixed(2)}' : '-';
  String get typeName => invoiceType == 'special' ? '增值税专用发票' : '普通发票';
}

/// 账单流水
class BillRecord {
  final int? billId;
  final String? billNo;
  final String? billType;
  final int? amount; // 分
  final int? balanceAfter; // 分
  final String? relatedType;
  final int? relatedId;
  final String? remark;
  final DateTime? createdAt;
  final String? orderNo;
  final String? workTitle;

  BillRecord({
    this.billId, this.billNo, this.billType, this.amount, this.balanceAfter,
    this.relatedType, this.relatedId, this.remark, this.createdAt,
    this.orderNo, this.workTitle,
  });

  factory BillRecord.fromJson(Map<String, dynamic> json) {
    return BillRecord(
      billId: json['billId'] as int?,
      billNo: json['billNo'] as String?,
      billType: json['billType'] as String?,
      amount: (json['amount'] as num?)?.toInt(),
      balanceAfter: (json['balanceAfter'] as num?)?.toInt(),
      relatedType: json['relatedType'] as String?,
      relatedId: json['relatedId'] as int?,
      remark: json['remark'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
      orderNo: json['orderNo'] as String?,
      workTitle: json['workTitle'] as String?,
    );
  }

  String get amountYuan {
    if (amount == null) return '-';
    final prefix = amount! >= 0 ? '+' : '';
    return '$prefix¥${(amount! / 100).toStringAsFixed(2)}';
  }

  String get typeLabel {
    switch (billType) {
      case 'income': return '订单收入';
      case 'withdraw': return '提现支出';
      case 'freeze': return '冻结';
      case 'settle': return '结算';
      default: return billType ?? '未知';
    }
  }
}

/// 资金托管汇总数据
class EscrowSummary {
  final List<Escrow> list;
  final int totalAmount; // 分
  final int pendingAmount; // 分
  final int total;
  EscrowSummary({required this.list, required this.totalAmount,
    required this.pendingAmount, required this.total});
}

// ==================== 工具函数 ====================

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return null;
}

/// 格式化日期
String formatDate(DateTime? dt) {
  if (dt == null) return '-';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

/// 格式化日期时间
String formatDateTime(DateTime? dt) {
  if (dt == null) return '-';
  return '${formatDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
