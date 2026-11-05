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

/// 订单状态（对齐后端状态机：confirmed(签合同) →双方签完自动→ paying →买方付款→ delivering →买方确认收货→ completed）
class OrderStatus {
  static const String confirmed = 'confirmed';            // 已确认（待双方签署合同）
  static const String paying = 'paying';                  // 付款中（合同已签，待买方付款）
  static const String delivering = 'delivering';          // 交割中
  static const String completed = 'completed';            // 已完成（收益入账）
  // 以下为遗留状态，仅历史数据只读展示，不再产生
  static const String escrowPending = 'escrow_pending';   // 已托管
  static const String cancelled = 'cancelled';            // 已取消
  static const String refunded = 'refunded';              // 已退款

  static String label(String? status) {
    switch (status) {
      case confirmed: return '待签署';
      case paying: return '付款中';
      case delivering: return '交割中';
      case completed: return '已完成';
      case escrowPending: return '已托管';
      case cancelled: return '已取消';
      case refunded: return '已退款';
      default: return status ?? '未知';
    }
  }
}

/// 合同签署状态
class ContractStatus {
  static const String pending = 'pending';                  // 待签署
  static const String partialSigned = 'partial_signed';    // 部分签署（一方已签）
  static const String completed = 'completed';              // 双方已签署
  static const String cancelled = 'cancelled';              // 已取消

  static String label(String? status) {
    switch (status) {
      case pending: return '待签署';
      case partialSigned: return '部分签署';
      case completed: return '双方已签';
      case cancelled: return '已取消';
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
  final int? contractId;      // 关联合同 ID
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
    this.contractId,
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
      contractId: (json['contractId'] as num?)?.toInt(),
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
  /// 验收轮次（仅 relatedType=demand_stage 的任务逐轮放款有值）
  final int? stageOrder;

  BillRecord({
    this.billId, this.billNo, this.billType, this.amount, this.balanceAfter,
    this.relatedType, this.relatedId, this.remark, this.createdAt,
    this.orderNo, this.workTitle, this.stageOrder,
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
      stageOrder: (json['stageOrder'] as num?)?.toInt(),
    );
  }

  String get amountYuan {
    if (amount == null) return '-';
    final prefix = amount! >= 0 ? '+' : '';
    return '$prefix¥${(amount! / 100).toStringAsFixed(2)}';
  }

  String get typeLabel {
    switch (billType) {
      case 'income': return fromDemandStage ? '任务轮次收益' : '订单收入';
      case 'withdraw': return '提现支出';
      case 'freeze': return '冻结';
      case 'settle': return '结算';
      default: return billType ?? '未知';
    }
  }

  /// 该笔收入是否来自征集任务的逐轮放款。
  bool get fromDemandStage => relatedType == 'demand_stage';

  /// 任务轮次副标题片段，例如「第2轮」。
  String? get roundLabel => stageOrder != null ? '第$stageOrder轮' : null;
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

// ==================== 合同域模型 ====================

/// 合同详情（含 HTML 内容、双方签署状态、签名/印章图片）
class ContractDetail {
  final int contractId;
  final String? contractNo;
  final String? contractType;
  final double? amount;          // 元（DECIMAL，保留小数，不可截断为 int）
  final int? orderId;
  final String? orderNo;
  final int? buyerId;
  final String? buyerName;
  final int? sellerId;
  final String? sellerName;
  final int? buyerSignStatus; // 0=未签, 1=已签
  final int? sellerSignStatus;
  final String? buyerSignTime;
  final String? sellerSignTime;
  final String? buyerSignatureImage;
  final String? buyerSealImage;
  final String? sellerSignatureImage;
  final String? sellerSealImage;
  final String? signedPdfUrl;
  final String? status;       // pending / partial_signed / completed
  final String? content;      // HTML 合同内容
  final String? templateId;   // 平台模板：TPL_COPYRIGHT_TRANSFER / TPL_COPYRIGHT_LICENSE
  final String? clausesText;  // 可编辑正文条款纯文本（null=模板默认）
  final String? sourceType;   // template 平台模板 / uploaded 用户上传 PDF
  final String? sourcePdfUrl; // 上传合同 PDF 文件 URL（uploaded 时）
  final int? pageCount;       // 上传 PDF 页数（uploaded 时）
  final List<String> pageImageUrls; // 上传件分页渲染图 URL（uploaded 时，供拖拽定位）
  final String? workTitle;
  final String? licenseType;
  final String? createdAt;

  const ContractDetail({
    required this.contractId,
    this.contractNo,
    this.contractType,
    this.amount,
    this.orderId,
    this.orderNo,
    this.buyerId,
    this.buyerName,
    this.sellerId,
    this.sellerName,
    this.buyerSignStatus,
    this.sellerSignStatus,
    this.buyerSignTime,
    this.sellerSignTime,
    this.buyerSignatureImage,
    this.buyerSealImage,
    this.sellerSignatureImage,
    this.sellerSealImage,
    this.signedPdfUrl,
    this.status,
    this.content,
    this.templateId,
    this.clausesText,
    this.sourceType,
    this.sourcePdfUrl,
    this.pageCount,
    this.pageImageUrls = const <String>[],
    this.workTitle,
    this.licenseType,
    this.createdAt,
  });

  factory ContractDetail.fromJson(Map<String, dynamic> json) {
    return ContractDetail(
      contractId: (json['contractId'] as num?)?.toInt() ?? 0,
      contractNo: json['contractNo'] as String?,
      contractType: json['contractType'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      orderId: (json['orderId'] as num?)?.toInt(),
      orderNo: json['orderNo'] as String?,
      buyerId: (json['buyerId'] as num?)?.toInt(),
      buyerName: json['buyerName'] as String?,
      sellerId: (json['sellerId'] as num?)?.toInt(),
      sellerName: json['sellerName'] as String?,
      buyerSignStatus: (json['buyerSignStatus'] as num?)?.toInt(),
      sellerSignStatus: (json['sellerSignStatus'] as num?)?.toInt(),
      buyerSignTime: json['buyerSignTime'] as String?,
      sellerSignTime: json['sellerSignTime'] as String?,
      buyerSignatureImage: json['buyerSignatureImage'] as String?,
      buyerSealImage: json['buyerSealImage'] as String?,
      sellerSignatureImage: json['sellerSignatureImage'] as String?,
      sellerSealImage: json['sellerSealImage'] as String?,
      signedPdfUrl: json['signedPdfUrl'] as String?,
      status: json['status'] as String?,
      content: json['content'] as String?,
      templateId: json['templateId'] as String?,
      clausesText: json['clausesText'] as String?,
      sourceType: json['sourceType'] as String?,
      sourcePdfUrl: json['sourcePdfUrl'] as String?,
      pageCount: (json['pageCount'] as num?)?.toInt(),
      pageImageUrls: (json['pageImageUrls'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[],
      workTitle: json['workTitle'] as String?,
      licenseType: json['licenseType'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }

  /// 买方是否已签署
  bool get isBuyerSigned => buyerSignStatus == 1;

  /// 卖方是否已签署
  bool get isSellerSigned => sellerSignStatus == 1;

  /// 合同是否已完成（双方均已签署）
  bool get isCompleted => status == ContractStatus.completed;

  /// 是否可编辑正文条款：待签署且双方均未签
  bool get isEditable =>
      status == ContractStatus.pending && !isBuyerSigned && !isSellerSigned;

  /// 是否为上传 PDF 件（走拖拽定位签署，不可在线编辑条款）
  bool get isUploaded => sourceType == 'uploaded';

  /// 是否为平台模板件（系统自动落章、可编辑条款）
  bool get isTemplate => !isUploaded;

  /// 合同状态标签
  String get statusLabel => ContractStatus.label(status);

  /// 金额展示（合同金额后端存元，保留两位小数）
  String get amountYuan => amount != null ? '¥${amount!.toStringAsFixed(2)}' : '-';
}

/// 平台合同模板（供切换模板时填充默认条款）。
class ContractTemplate {
  final String templateId;
  final String name;
  final String defaultClausesText;

  const ContractTemplate({
    required this.templateId,
    required this.name,
    this.defaultClausesText = '',
  });

  factory ContractTemplate.fromJson(Map<String, dynamic> json) {
    return ContractTemplate(
      templateId: json['templateId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      defaultClausesText: json['defaultClausesText'] as String? ?? '',
    );
  }
}

// ==================== 任务广场（需求悬赏） ====================

/// 征集状态
class DemandStatus {
  static const String open = 'open';
  static const String inProgress = 'in_progress';
  static const String completed = 'completed';
  static const String closed = 'closed';
  static const String selected = 'selected';
  static const String failed = 'failed';

  static String label(String? status) {
    switch (status) {
      case open: return '待接单';
      case inProgress: return '进行中';
      case completed: return '已完成';
      case closed: return '已关闭';
      case selected: return '已选定';
      case failed: return '已失败';
      default: return status ?? '未知';
    }
  }
}

/// 需求任务托管资金状态（入账走支付宝沙箱，出账记账）
class DemandEscrowStatus {
  static const String none = 'none';
  static const String pendingPayment = 'pending_payment';
  static const String escrowed = 'escrowed';
  static const String released = 'released';
  static const String refundedToPublisher = 'refunded_to_publisher';

  static String label(String? status) {
    switch (status) {
      case none: return '无托管';
      case pendingPayment: return '待付托管';
      case escrowed: return '已托管';
      case released: return '已放款';
      case refundedToPublisher: return '已退回发布者';
      default: return status ?? '未知';
    }
  }
}

/// 需求任务押金资金状态
/// 押金是创作者缴的履约保证金，不是发布者托管的预算款，
/// held 不能译作「已托管」（与 DemandEscrowStatus.escrowed 撞词，页面上就分不出两笔钱）
class DemandDepositStatus {
  static const String none = 'none';
  static const String held = 'held';
  static const String refunded = 'refunded';
  static const String forfeited = 'forfeited';

  static String label(String? status) {
    switch (status) {
      case none: return '未缴';
      case held: return '在押';
      case refunded: return '已退还';
      case forfeited: return '已没收';
      default: return status ?? '未知';
    }
  }
}

/// 投稿状态
class SubmissionStatus {
  static const String submitted = 'submitted';
  static const String shortlisted = 'shortlisted';
  static const String accepted = 'accepted';
  static const String rejected = 'rejected';

  static String label(String? status) {
    switch (status) {
      case submitted: return '已投稿';
      case shortlisted: return '入围';
      case accepted: return '已选用';
      case rejected: return '未选用';
      default: return status ?? '未知';
    }
  }
}

/// 征集任务模型
class DemandTask {
  final int? demandId;
  final String? demandNo;
  final int? clientId;
  final String? title;
  final int? genreId;
  final String? tags;
  final int? budget; // 分
  final DateTime? deadline;
  final String? requirement;
  final String? contactInfo;
  final int? submissionCount;
  final int? totalEpisodes;
  final String? status;
  final DateTime? createdAt;
  final String? clientName;
  // 接单制
  final int? acceptedCreatorId;
  final DateTime? acceptedAt;
  final int? durationHours;
  final DateTime? dueAt;
  final int? isOverdue;
  final String? acceptedCreatorName;
  // 逐轮托管押金（金额均为分）
  final int? escrowAmount;
  final String? escrowStatus;
  final int? depositAmount;
  final String? depositStatus;
  final DateTime? depositPaidAt;
  final DateTime? depositSettledAt;
  final String? failReason;
  final DateTime? failAt;

  const DemandTask({
    this.demandId, this.demandNo, this.clientId, this.title, this.genreId,
    this.tags, this.budget, this.deadline, this.requirement, this.contactInfo,
    this.submissionCount, this.totalEpisodes, this.status, this.createdAt, this.clientName,
    this.acceptedCreatorId, this.acceptedAt, this.durationHours, this.dueAt,
    this.isOverdue, this.acceptedCreatorName,
    this.escrowAmount, this.escrowStatus, this.depositAmount, this.depositStatus,
    this.depositPaidAt, this.depositSettledAt, this.failReason, this.failAt,
  });

  /// 是否已完成托管付款（广场可抢/可接单前置）。
  bool get isEscrowed => escrowStatus == DemandEscrowStatus.escrowed;
  /// 是否待发布者支付托管。
  bool get isEscrowPending => escrowStatus == DemandEscrowStatus.pendingPayment;

  /// 托管额（元，用于展示）。
  String get escrowYuanText => _fenToYuanText(escrowAmount);
  /// 押金（元，用于展示）。
  String get depositYuanText => _fenToYuanText(depositAmount);

  static String _fenToYuanText(int? fen) {
    if (fen == null) return '0.00';
    return (fen / 100).toStringAsFixed(2);
  }

  /// 接单制状态文案；逾期优先于进行中展示。
  String get statusLabel {
    if (isOverdue == 1) return '已逾期';
    switch (status) {
      case 'open': return '待接单';
      case 'in_progress': return '进行中';
      case 'completed': return '已完成';
      case 'selected': return '已选定';
      case 'closed': return '已关闭';
      case 'failed': return '已失败';
      default: return status ?? '未知';
    }
  }

  factory DemandTask.fromJson(Map<String, dynamic> json) {
    return DemandTask(
      demandId: (json['demandId'] as num?)?.toInt(),
      demandNo: json['demandNo'] as String?,
      clientId: (json['clientId'] as num?)?.toInt(),
      title: json['title'] as String?,
      genreId: (json['genreId'] as num?)?.toInt(),
      tags: json['tags'] as String?,
      budget: (json['budget'] as num?)?.toInt(),
      deadline: _parseDateTime(json['deadline']),
      requirement: json['requirement'] as String?,
      contactInfo: json['contactInfo'] as String?,
      submissionCount: (json['submissionCount'] as num?)?.toInt(),
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt(),
      status: json['status'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
      clientName: json['clientName'] as String?,
      acceptedCreatorId: (json['acceptedCreatorId'] as num?)?.toInt(),
      acceptedAt: _parseDateTime(json['acceptedAt']),
      durationHours: (json['durationHours'] as num?)?.toInt(),
      dueAt: _parseDateTime(json['dueAt']),
      isOverdue: (json['overdue'] as num?)?.toInt() ?? (json['isOverdue'] as num?)?.toInt(),
      acceptedCreatorName: json['acceptedCreatorName'] as String?,
      escrowAmount: (json['escrowAmount'] as num?)?.toInt(),
      escrowStatus: json['escrowStatus'] as String?,
      depositAmount: (json['depositAmount'] as num?)?.toInt(),
      depositStatus: json['depositStatus'] as String?,
      depositPaidAt: _parseDateTime(json['depositPaidAt']),
      depositSettledAt: _parseDateTime(json['depositSettledAt']),
      failReason: json['failReason'] as String?,
      failAt: _parseDateTime(json['failAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'genreId': genreId,
    'budget': budget,
    'deadline': deadline != null ? '${deadline!.year}-${deadline!.month.toString().padLeft(2, '0')}-${deadline!.day.toString().padLeft(2, '0')}' : null,
    'requirement': requirement,
    'contactInfo': contactInfo,
    'tags': tags,
    'totalEpisodes': totalEpisodes,
    'durationHours': durationHours,
  };
}

/// 投稿模型
class DemandSubmission {
  final int? submissionId;
  final int? demandId;
  final int? workId;
  final int? submitterId;
  final String? status;
  final String? submitMessage;
  final String? reviewRemark;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final String? workTitle;
  final String? submitterName;

  const DemandSubmission({
    this.submissionId, this.demandId, this.workId, this.submitterId,
    this.status, this.submitMessage, this.reviewRemark, this.reviewedAt,
    this.createdAt, this.workTitle, this.submitterName,
  });

  factory DemandSubmission.fromJson(Map<String, dynamic> json) {
    return DemandSubmission(
      submissionId: (json['submissionId'] as num?)?.toInt(),
      demandId: (json['demandId'] as num?)?.toInt(),
      workId: (json['workId'] as num?)?.toInt(),
      submitterId: (json['submitterId'] as num?)?.toInt(),
      status: json['status'] as String?,
      submitMessage: json['submitMessage'] as String?,
      reviewRemark: json['reviewRemark'] as String?,
      reviewedAt: _parseDateTime(json['reviewedAt']),
      createdAt: _parseDateTime(json['createdAt']),
      workTitle: json['workTitle'] as String?,
      submitterName: json['submitterName'] as String?,
    );
  }
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

// ==================== 验收轮次模型 ====================

class DemandStage {
  final int? stageId;
  final int? demandId;
  final int? stageOrder;
  final int? episodeTo;
  final int? amount; // 分
  final String? status; // pending/ai_reviewing/submitted/approved/rejected
  final String? deliverableDesc;
  final String? deliverableUrl;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? rejectReason;
  final int? releaseFlag;
  // 逐轮独立计时
  final int? durationDays;
  final int? durationHours;
  final DateTime? startedAt;
  final DateTime? dueAt;
  final int? isOverdue;
  // 交付作品与延期
  final int? workId;
  final String? workTitle;
  // AI 审核（提交后、人工验收前的自动前置门）
  final int? aiScore;
  final String? aiResult;
  final DateTime? aiReviewedAt;
  final String? extendStatus; // null=无申请 / pending / approved / rejected（最近一次快照）
  final int? extendDays;
  final int? extendHours;
  final String? extendReason;
  final DateTime? extendAppliedAt;

  const DemandStage({
    this.stageId, this.demandId, this.stageOrder, this.episodeTo, this.amount,
    this.status, this.deliverableDesc, this.deliverableUrl,
    this.submittedAt, this.reviewedAt, this.rejectReason, this.releaseFlag,
    this.durationDays, this.durationHours, this.startedAt, this.dueAt, this.isOverdue,
    this.workId, this.workTitle, this.extendStatus, this.extendDays, this.extendHours,
    this.extendReason, this.extendAppliedAt,
    this.aiScore, this.aiResult, this.aiReviewedAt,
  });

  factory DemandStage.fromJson(Map<String, dynamic> json) {
    return DemandStage(
      stageId: (json['stageId'] as num?)?.toInt(),
      demandId: (json['demandId'] as num?)?.toInt(),
      stageOrder: (json['stageOrder'] as num?)?.toInt(),
      episodeTo: (json['episodeTo'] as num?)?.toInt(),
      amount: (json['amount'] as num?)?.toInt(),
      status: json['status'] as String?,
      deliverableDesc: json['deliverableDesc'] as String?,
      deliverableUrl: json['deliverableUrl'] as String?,
      submittedAt: _parseDateTime(json['submittedAt']),
      reviewedAt: _parseDateTime(json['reviewedAt']),
      rejectReason: json['rejectReason'] as String?,
      releaseFlag: (json['releaseFlag'] as num?)?.toInt(),
      durationDays: (json['durationDays'] as num?)?.toInt(),
      durationHours: (json['durationHours'] as num?)?.toInt(),
      startedAt: _parseDateTime(json['startedAt']),
      dueAt: _parseDateTime(json['dueAt']),
      isOverdue: (json['overdue'] as num?)?.toInt() ?? (json['isOverdue'] as num?)?.toInt(),
      workId: (json['workId'] as num?)?.toInt(),
      workTitle: json['workTitle'] as String?,
      aiScore: (json['aiScore'] as num?)?.toInt(),
      aiResult: json['aiResult'] as String?,
      aiReviewedAt: _parseDateTime(json['aiReviewedAt']),
      extendStatus: json['extendStatus'] as String?,
      extendDays: (json['extendDays'] as num?)?.toInt(),
      extendHours: (json['extendHours'] as num?)?.toInt(),
      extendReason: json['extendReason'] as String?,
      extendAppliedAt: _parseDateTime(json['extendAppliedAt']),
    );
  }

  /// 状态标签文本
  String get statusLabel {
    switch (status) {
      case 'pending': return '待交付';
      case 'ai_reviewing': return 'AI审核中';
      case 'submitted': return '待审核';
      case 'approved': return '已通过';
      case 'rejected': return '已驳回';
      default: return status ?? '';
    }
  }

  /// 本轮时限文案（天+小时）。
  String get durationText {
    final d = durationDays ?? 0;
    final h = durationHours ?? 0;
    if (d > 0 && h > 0) return '$d 天 $h 小时';
    if (d > 0) return '$d 天';
    if (h > 0) return '$h 小时';
    return '-';
  }

  /// 绝对截止文案：“X月X日 HH:mm”；未激活返回 null。
  String? get absoluteDueText {
    if (dueAt == null) return null;
    final dt = dueAt!.toLocal();
    return '${dt.month}月${dt.day}日 '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 本轮是否处于审核暂停计时（AI审核中/待人工验收，审核耗时均不计入时限）。
  bool get isPausedForReview => status == 'submitted' || status == 'ai_reviewing';

  /// 是否处于 AI 审核中（后台跑完前不可交付/不可验收/不可延期）。
  bool get isAiReviewing => status == 'ai_reviewing';

  /// AI 审核结论一行文案：分数 + 结果；未审核返回 null。
  String? get aiVerdictText {
    if (aiScore == null && aiReviewedAt == null) return null;
    if (aiScore == null) return 'AI审核：未评分（已转人工验收）';
    final pass = aiScore! >= 60;
    return 'AI审核：$aiScore分 · ${pass ? '通过，待发布者验收' : '未通过，已自动打回'}';
  }

  /// 是否有待处理的延时申请（轮次行上的最近一次快照；完整历史见 DemandExtendApply）。
  bool get hasPendingExtend => extendStatus == 'pending';

  /// 延时申请量文案（天+小时）。
  String get extendAskText {
    final d = extendDays ?? 0;
    final h = extendHours ?? 0;
    if (d > 0 && h > 0) return '$d天$h小时';
    if (d > 0) return '$d天';
    if (h > 0) return '$h小时';
    return '-';
  }

  /// 本轮是否已逾期（活动轮且当前时间超过 dueAt；待审核期间计时暂停不算逾期）。
  bool get isOverdueNow {
    if (isPausedForReview) return false;
    if (isOverdue == 1) return true;
    if (status == 'approved' || dueAt == null) return false;
    return DateTime.now().isAfter(dueAt!);
  }
}

/// 延时历史记录（一条动作一行，通过/驳回均保留）。
/// [applyType] 区分来源：request=创作者申请延时（待发布者处理），self=发布者自主延时（写入即生效）。
class DemandExtendApply {
  final int? applyId;
  final int? demandId;
  final int? stageId;
  final int? stageOrder;
  final int? days;
  final int? hours;
  final String? reason;
  final String? status; // pending / approved / rejected
  final String? applyType; // request / self
  final DateTime? appliedAt;
  final DateTime? decidedAt;
  /// 本次动作生效后的轮次截止时间：自主延时/申请通过时有值，待处理与驳回为空
  final DateTime? dueAfter;

  const DemandExtendApply({
    this.applyId, this.demandId, this.stageId, this.stageOrder,
    this.days, this.hours, this.reason, this.status, this.applyType,
    this.appliedAt, this.decidedAt, this.dueAfter,
  });

  factory DemandExtendApply.fromJson(Map<String, dynamic> json) {
    return DemandExtendApply(
      applyId: (json['applyId'] as num?)?.toInt(),
      demandId: (json['demandId'] as num?)?.toInt(),
      stageId: (json['stageId'] as num?)?.toInt(),
      stageOrder: (json['stageOrder'] as num?)?.toInt(),
      days: (json['days'] as num?)?.toInt(),
      hours: (json['hours'] as num?)?.toInt(),
      reason: json['reason'] as String?,
      status: json['status'] as String?,
      applyType: json['applyType'] as String?,
      appliedAt: _parseDateTime(json['appliedAt']),
      decidedAt: _parseDateTime(json['decidedAt']),
      dueAfter: _parseDateTime(json['dueAfter']),
    );
  }

  bool get isPending => status == 'pending';

  /// 是否发布者自主延时（无需审核，落记录即已生效）。
  bool get isSelf => applyType == 'self';

  /// 记录行前缀文案：自主延时 / 申请延时。
  String get sourceLabel => isSelf ? '自主延时' : '申请延时';

  /// 处理结果文案（自主延时没有审核环节，直接标已生效）。
  String get statusLabel {
    if (isSelf) return '已生效';
    switch (status) {
      case 'pending': return '待处理';
      case 'approved': return '已同意';
      case 'rejected': return '已拒绝';
      default: return status ?? '';
    }
  }

  /// 申请量文案（天+小时）。
  String get askText {
    final d = days ?? 0;
    final h = hours ?? 0;
    if (d > 0 && h > 0) return '$d天$h小时';
    if (d > 0) return '$d天';
    if (h > 0) return '$h小时';
    return '-';
  }

  /// 申请时间文案“X月X日 HH:mm”。
  String get appliedText {
    final dt = appliedAt?.toLocal();
    if (dt == null) return '';
    return '${dt.month}月${dt.day}日 '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 顺延后新截止文案“X月X日 HH:mm”（待处理/驳回无值，返回空串）。
  String get dueAfterText {
    final dt = dueAfter?.toLocal();
    if (dt == null) return '';
    return '${dt.month}月${dt.day}日 '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 可交付作品（任务交付选择器：本人、非已上架售卖）。
class DeliverableWork {
  final int workId;
  final String? title;
  final String? status;
  final DateTime? updateTime;

  const DeliverableWork({
    required this.workId,
    this.title,
    this.status,
    this.updateTime,
  });

  factory DeliverableWork.fromJson(Map<String, dynamic> json) {
    return DeliverableWork(
      workId: (json['workId'] as num?)?.toInt() ?? 0,
      title: json['title'] as String?,
      status: json['status'] as String?,
      updateTime: _parseDateTime(json['updateTime']),
    );
  }

  /// 状态展示文案（交付选择器只展示非 on_shelf 作品）。
  String get statusLabel {
    switch (status) {
      case 'draft': return '草稿';
      case 'reviewing': return '审核中';
      case 'rejected': return '审核驳回';
      case 'off_shelf': return '已下架';
      default: return status ?? '';
    }
  }
}
