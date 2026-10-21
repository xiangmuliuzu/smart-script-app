/// 版权管理模块数据模型（App 端）。
///
/// 接口口径（后端 smartscript-content）：
///   版权申请：
///     GET  /api/v1/app/content/copyright/application/list   → 我的申请列表
///     GET  /api/v1/app/content/copyright/application/{id}   → 申请详情
///     POST /api/v1/app/content/copyright/application/apply  → 提交申请
///     POST /api/v1/app/content/copyright/application/resubmit → 重新提交
///   
///   版权证书：
///     GET  /api/v1/app/content/copyright/cert/list          → 我的证书列表
///     GET  /api/v1/app/content/copyright/cert/{id}          → 证书详情
///     GET  /api/v1/app/content/copyright/cert/{id}/download → 下载证书PDF
///   
///   版权中心配置：
///     GET  /api/v1/app/content/copyright/config/active      → 获取可用版权中心
///
/// 全部为标准若依信封 {code, message, data}。
library;

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

String _text(dynamic value) => value == null ? '' : value.toString();

String? _textOrNull(dynamic value) => value?.toString();

/// 版权申请状态枚举
class CopyrightApplicationStatus {
  static const String pending = 'pending'; // 待审核
  static const String approved = 'approved'; // 待提交
  static const String submitted = 'submitted'; // 待提交到第三方
  static const String reviewing = 'reviewing'; // 审核中
  static const String certificated = 'certificated'; // 已发证
  static const String rejected = 'rejected'; // 已驳回
}

/// 版权证书状态枚举
class CopyrightCertStatus {
  static const String pending = 'pending'; // 申请中
  static const String issued = 'issued'; // 已签发
  static const String expired = 'expired'; // 已失效
}

/// 版权申请记录
class CopyrightApplication {
  const CopyrightApplication({
    required this.applyId,
    this.applyNo = '',
    this.workId = 0,
    this.workName = '',
    this.workType,
    this.workCategory,
    this.workIntro,
    this.workCoverUrl,
    this.workCompletionDate,
    this.workPublishDate,
    this.workFileUrl,
    this.identityProofUrl,
    this.creationProofUrl,
    this.otherMaterialsUrls,
    // 新增分类材料字段
    this.originalityProof,
    this.authorIdentityDoc,
    this.creationProcess,
    this.otherProof,
    this.userId = 0,
    this.userName = '',
    this.copyrightCenter = '',
    this.centerName = '',
    this.externalApplyNo,
    this.status = '',
    this.certNo,
    this.certId,
    this.certUrl,
    this.rejectReason,
    this.createTime,
    this.submitTime,
    this.certTime,
    this.remark,
  });

  final int applyId;
  final String applyNo;
  final int workId;
  final String workName;
  final String? workType;
  final String? workCategory;
  final String? workIntro;
  final String? workCoverUrl;
  final String? workCompletionDate;
  final String? workPublishDate;
  final String? workFileUrl;
  final String? identityProofUrl;
  final String? creationProofUrl;
  final String? otherMaterialsUrls;
  // 新增分类材料字段（对应后端的新字段）
  final String? originalityProof;        // 原创性证明材料（JSON数组）
  final String? authorIdentityDoc;       // 作者身份证明材料（JSON数组）
  final String? creationProcess;         // 创作过程材料（JSON数组）
  final String? otherProof;              // 其他辅助证明材料（JSON数组）
  final int userId;
  final String userName;
  final String copyrightCenter;
  final String centerName;
  final String? externalApplyNo;
  final String status;
  final String? certNo;
  final int? certId;
  final String? certUrl;
  final String? rejectReason;
  final String? createTime;
  final String? submitTime;
  final String? certTime;
  final String? remark;

  /// 状态中文标签
  String get statusLabel {
    switch (status) {
      case CopyrightApplicationStatus.pending:
        return '待审核';
      case CopyrightApplicationStatus.approved:
        return '待提交';
      case CopyrightApplicationStatus.submitted:
        return '待提交到第三方';
      case CopyrightApplicationStatus.reviewing:
        return '审核中';
      case CopyrightApplicationStatus.certificated:
        return '已发证';
      case CopyrightApplicationStatus.rejected:
        return '已驳回';
      default:
        return status.isEmpty ? '未知' : status;
    }
  }

  /// 状态描述
  String get statusDescription {
    switch (status) {
      case CopyrightApplicationStatus.pending:
        return '平台正在审核您的申请，请耐心等待';
      case CopyrightApplicationStatus.approved:
        return '审核通过，等待提交到版权中心';
      case CopyrightApplicationStatus.submitted:
        return '等待提交到版权中心';
      case CopyrightApplicationStatus.reviewing:
        return '已提交到${centerName.isNotEmpty ? centerName : '版权中心'}，正在审核中';
      case CopyrightApplicationStatus.certificated:
        return '恭喜！版权证书已签发';
      case CopyrightApplicationStatus.rejected:
        return rejectReason ?? '申请被驳回';
      default:
        return '';
    }
  }

  /// 是否可重新提交
  bool get canResubmit => status == CopyrightApplicationStatus.rejected;

  /// 是否已发证
  bool get isCertificated => status == CopyrightApplicationStatus.certificated;

  factory CopyrightApplication.fromJson(Map<String, dynamic> json) =>
      CopyrightApplication(
        applyId: _int(json['applyId']),
        applyNo: _text(json['applyNo']),
        workId: _int(json['workId']),
        workName: _text(json['workName']),
        workType: _textOrNull(json['workType']),
        workCategory: _textOrNull(json['workCategory']),
        workIntro: _textOrNull(json['workIntro']),
        workCoverUrl: _textOrNull(json['workCoverUrl']),
        workCompletionDate: _textOrNull(json['workCompletionDate']),
        workPublishDate: _textOrNull(json['workPublishDate']),
        workFileUrl: _textOrNull(json['workFileUrl']),
        identityProofUrl: _textOrNull(json['identityProofUrl']),
        creationProofUrl: _textOrNull(json['creationProofUrl']),
        otherMaterialsUrls: _textOrNull(json['otherMaterialsUrls']),
        // 新增分类材料字段
        originalityProof: _textOrNull(json['originalityProof']),
        authorIdentityDoc: _textOrNull(json['authorIdentityDoc']),
        creationProcess: _textOrNull(json['creationProcess']),
        otherProof: _textOrNull(json['otherProof']),
        userId: _int(json['userId']),
        userName: _text(json['userName']),
        copyrightCenter: _text(json['copyrightCenter']),
        centerName: _text(json['centerName']),
        externalApplyNo: _textOrNull(json['externalApplyNo']),
        status: _text(json['status']),
        certNo: _textOrNull(json['certNo']),
        certId: json['certId'] != null ? _int(json['certId']) : null,
        certUrl: _textOrNull(json['certUrl']),
        rejectReason: _textOrNull(json['rejectReason']),
        createTime: _textOrNull(json['createTime']),
        submitTime: _textOrNull(json['submitTime']),
        certTime: _textOrNull(json['certTime']),
        remark: _textOrNull(json['remark']),
      );
}

/// 版权证书
class CopyrightCert {
  const CopyrightCert({
    required this.certId,
    this.certNo = '',
    this.workId = 0,
    this.workName = '',
    this.userId = 0,
    this.userName = '',
    this.status = '',
    this.blockchainHash,
    this.certUrl,
    this.applyTime,
    this.certTime,
    this.remark,
  });

  final int certId;
  final String certNo;
  final int workId;
  final String workName;
  final int userId;
  final String userName;
  final String status;
  final String? blockchainHash;
  final String? certUrl;
  final String? applyTime;
  final String? certTime;
  final String? remark;

  /// 状态中文标签
  String get statusLabel {
    switch (status) {
      case CopyrightCertStatus.pending:
        return '申请中';
      case CopyrightCertStatus.issued:
        return '已签发';
      case CopyrightCertStatus.expired:
        return '已失效';
      default:
        return status.isEmpty ? '未知' : status;
    }
  }

  /// 是否已签发
  bool get isIssued => status == CopyrightCertStatus.issued;

  factory CopyrightCert.fromJson(Map<String, dynamic> json) => CopyrightCert(
        certId: _int(json['certId']),
        certNo: _text(json['certNo']),
        workId: _int(json['workId']),
        workName: _text(json['workName']),
        userId: _int(json['userId']),
        userName: _text(json['userName']),
        status: _text(json['status']),
        blockchainHash: _textOrNull(json['blockchainHash']),
        certUrl: _textOrNull(json['certUrl']),
        applyTime: _textOrNull(json['applyTime']),
        certTime: _textOrNull(json['certTime']),
        remark: _textOrNull(json['remark']),
      );
}

/// 版权中心配置
class CopyrightCenter {
  const CopyrightCenter({
    required this.centerCode,
    this.centerName = '',
  });

  final String centerCode;
  final String centerName;

  factory CopyrightCenter.fromJson(Map<String, dynamic> json) =>
      CopyrightCenter(
        centerCode: _text(json['centerCode']),
        centerName: _text(json['centerName']),
      );
}

/// 版权申请提交DTO
class CopyrightApplyDTO {
  const CopyrightApplyDTO({
    required this.workId,
    required this.workType,
    required this.completeTime,
    required this.copyrightCenter,
    this.fileUrl,
    this.originalityProof,
    this.authorIdentityDoc,
    this.creationProcess,
    this.otherProof,
    this.remark,
  });

  final int workId;
  final String workType;
  final String completeTime;
  final String copyrightCenter;
  
  // 兼容旧版：单个文件URL
  final String? fileUrl;
  
  // 新版分类材料（字段名与后端一致）
  final String? originalityProof;    // 独创性证明材料（JSON数组字符串）
  final String? authorIdentityDoc;   // 作者身份证明材料（JSON数组字符串）
  final String? creationProcess;     // 创作过程材料（JSON数组字符串）
  final String? otherProof;          // 其他辅助证明材料（JSON数组字符串）
  
  final String? remark;

  Map<String, dynamic> toJson() => {
        'workId': workId,
        'workType': workType,
        'completeTime': completeTime,
        'copyrightCenter': copyrightCenter,
        if (fileUrl != null) 'fileUrl': fileUrl,
        if (originalityProof != null) 'originalityProofUrls': originalityProof,
        if (authorIdentityDoc != null) 'authorIdentityDocUrls': authorIdentityDoc,
        if (creationProcess != null) 'creationProcessUrls': creationProcess,
        if (otherProof != null) 'otherProofUrls': otherProof,
        if (remark != null) 'remark': remark,
      };
}

/// 版权申请重新提交DTO
class CopyrightResubmitDTO {
  const CopyrightResubmitDTO({
    required this.originalApplyId,
    required this.workType,
    required this.completeTime,
    this.fileUrl,
    this.originalityProof,
    this.authorIdentityDoc,
    this.creationProcess,
    this.otherProof,
    this.remark,
  });

  final int originalApplyId;
  final String workType;
  final String completeTime;
  final String? fileUrl;
  final String? originalityProof;      // 独创性证明材料（JSON数组字符串）
  final String? authorIdentityDoc;     // 作者身份证明材料（JSON数组字符串）
  final String? creationProcess;       // 创作过程说明材料（JSON数组字符串）
  final String? otherProof;            // 其他辅助证明材料（JSON数组字符串）
  final String? remark;

  Map<String, dynamic> toJson() => {
        'originalApplyId': originalApplyId,
        'workType': workType,
        'completeTime': completeTime,
        if (fileUrl != null) 'fileUrl': fileUrl,
        if (originalityProof != null) 'originalityProofUrls': originalityProof,
        if (authorIdentityDoc != null) 'authorIdentityDocUrls': authorIdentityDoc,
        if (creationProcess != null) 'creationProcessUrls': creationProcess,
        if (otherProof != null) 'otherProofUrls': otherProof,
        if (remark != null) 'remark': remark,
      };
}

/// 我的作品简要信息（用于申请时选择）
class MyWorkBrief {
  const MyWorkBrief({
    required this.workId,
    this.title = '',
    this.coverUrl,
  });

  final int workId;
  final String title;
  final String? coverUrl;
  
  // 别名属性，兼容旧代码
  String get workName => title;

  factory MyWorkBrief.fromJson(Map<String, dynamic> json) => MyWorkBrief(
        workId: _int(json['workId']),
        title: _text(json['title'] ?? json['workName'] ?? json['workTitle']),
        // /users/me/works 返回 cover；旧口径 coverUrl
        coverUrl: _textOrNull(json['coverUrl'] ?? json['cover']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyWorkBrief && runtimeType == other.runtimeType && workId == other.workId;

  @override
  int get hashCode => workId.hashCode;
}

// ==================== 版权交割模型 ====================

/// 交割文件
class DeliveryFile {
  final String fileName;
  final String fileType;  // cert/source/doc/other
  final String fileUrl;
  final int fileSize;

  const DeliveryFile({
    required this.fileName,
    required this.fileType,
    required this.fileUrl,
    required this.fileSize,
  });

  factory DeliveryFile.fromJson(Map<String, dynamic> json) {
    return DeliveryFile(
      fileName: _text(json['fileName']),
      fileType: _text(json['fileType']),
      fileUrl: _text(json['fileUrl']),
      fileSize: _int(json['fileSize']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'fileType': fileType,
      'fileUrl': fileUrl,
      'fileSize': fileSize,
    };
  }
}

/// 版权交割记录
class CopyrightDelivery {
  final int deliveryId;
  final String deliveryNo;
  final int orderId;
  final String orderNo;
  final int workId;
  final String workTitle;
  final String workCover;
  final int buyerId;
  final String buyerName;
  final int sellerId;
  final String sellerName;
  final double amount;
  final String licenseType;      // exclusive/non_exclusive
  final String status;           // pending_upload/pending_confirm/completed/cancelled
  final String contractNo;
  final String? contractSignTime;
  final String? certNo;
  final List<DeliveryFile>? files;
  final String? remark;
  final String? uploadTime;
  final String? confirmTime;
  final String? completedTime;
  final String createTime;

  const CopyrightDelivery({
    required this.deliveryId,
    required this.deliveryNo,
    required this.orderId,
    required this.orderNo,
    required this.workId,
    required this.workTitle,
    required this.workCover,
    required this.buyerId,
    required this.buyerName,
    required this.sellerId,
    required this.sellerName,
    required this.amount,
    required this.licenseType,
    required this.status,
    required this.contractNo,
    this.contractSignTime,
    this.certNo,
    this.files,
    this.remark,
    this.uploadTime,
    this.confirmTime,
    this.completedTime,
    required this.createTime,
  });

  factory CopyrightDelivery.fromJson(Map<String, dynamic> json) {
    List<DeliveryFile>? filesList;
    if (json['files'] != null) {
      final filesData = json['files'] as List<dynamic>;
      filesList = filesData
          .map((e) => DeliveryFile.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return CopyrightDelivery(
      deliveryId: _int(json['deliveryId']),
      deliveryNo: _text(json['deliveryNo']),
      orderId: _int(json['orderId']),
      orderNo: _text(json['orderNo']),
      workId: _int(json['workId']),
      workTitle: _text(json['workTitle']),
      workCover: _text(json['workCover']),
      buyerId: _int(json['buyerId']),
      buyerName: _text(json['buyerName']),
      sellerId: _int(json['sellerId']),
      sellerName: _text(json['sellerName']),
      amount: _double(json['amount']),
      licenseType: _text(json['licenseType']),
      status: _text(json['status']),
      contractNo: _text(json['contractNo']),
      contractSignTime: _textOrNull(json['contractSignTime']),
      certNo: _textOrNull(json['certNo']),
      files: filesList,
      remark: _textOrNull(json['remark']),
      uploadTime: _textOrNull(json['uploadTime']),
      confirmTime: _textOrNull(json['confirmTime']),
      completedTime: _textOrNull(json['completedTime']),
      createTime: _text(json['createTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deliveryId': deliveryId,
      'deliveryNo': deliveryNo,
      'orderId': orderId,
      'orderNo': orderNo,
      'workId': workId,
      'workTitle': workTitle,
      'workCover': workCover,
      'buyerId': buyerId,
      'buyerName': buyerName,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'amount': amount,
      'licenseType': licenseType,
      'status': status,
      'contractNo': contractNo,
      'contractSignTime': contractSignTime,
      'certNo': certNo,
      'files': files?.map((e) => e.toJson()).toList(),
      'remark': remark,
      'uploadTime': uploadTime,
      'confirmTime': confirmTime,
      'completedTime': completedTime,
      'createTime': createTime,
    };
  }
}

/// 交割列表响应
class DeliveryListResponse {
  final int total;
  final List<CopyrightDelivery> list;

  const DeliveryListResponse({
    required this.total,
    required this.list,
  });

  factory DeliveryListResponse.fromJson(Map<String, dynamic> json) {
    final listData = json['list'] as List<dynamic>? ?? [];
    return DeliveryListResponse(
      total: _int(json['total']),
      list: listData
          .map((e) => CopyrightDelivery.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ==================== 扩展方法 ====================

extension DeliveryStatusExtension on String {
  String get deliveryStatusName {
    switch (this) {
      case 'pending_upload':
        return '待上传';
      case 'pending_confirm':
        return '待确认';
      case 'completed':
        return '已完成';
      case 'cancelled':
        return '已取消';
      default:
        return this;
    }
  }
}

extension LicenseTypeExtension on String {
  String get licenseTypeName {
    switch (this) {
      case 'exclusive':
        return '独家授权';
      case 'non_exclusive':
        return '非独家授权';
      default:
        return this;
    }
  }
}

extension FileTypeExtension on String {
  String get fileTypeName {
    switch (this) {
      case 'cert':
        return '版权证书';
      case 'source':
        return '作品源文件';
      case 'doc':
        return '授权文档';
      case 'other':
        return '其他材料';
      default:
        return this;
    }
  }
}

// 版权申请状态名称扩展
extension CopyrightApplicationStatusExtension on String {
  String get statusName {
    switch (this) {
      case CopyrightApplicationStatus.pending:
        return '待审核';
      case CopyrightApplicationStatus.approved:
        return '待提交';
      case CopyrightApplicationStatus.submitted:
        return '待提交';
      case CopyrightApplicationStatus.reviewing:
        return '审核中';
      case CopyrightApplicationStatus.certificated:
        return '已发证';
      case CopyrightApplicationStatus.rejected:
        return '已驳回';
      default:
        return this;
    }
  }
}
