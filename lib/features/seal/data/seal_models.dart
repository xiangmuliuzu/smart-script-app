/// 印章模块数据模型（App 端用户印章管理）。
///
/// 接口口径（后端 smartscript-content，App 用户侧）：
///   GET  /api/v1/content/copyright-seals           → 我的印章列表
///   GET  /api/v1/content/copyright-seals/{sealId}  → 印章详情（含材料、日志）
///   POST /api/v1/content/copyright-seals           → 上传印章图片（首次提交）
///   POST /api/v1/content/copyright-seals/{sealId}/materials → 补充审核材料
///   PUT  /api/v1/content/copyright-seals/{sealId}/resubmit  → 重新提交印章
///   PUT  /api/v1/content/copyright-seals/{sealId}/disable   → 停用印章
///
/// 全部为标准若依信封 {code, message, data}。
library;

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _text(dynamic value) => value == null ? '' : value.toString();

String? _textOrNull(dynamic value) => value?.toString();

/// 印章（含审核状态、印章状态、驳回原因）。
class SealItem {
  const SealItem({
    required this.sealId,
    this.sealName = '',
    this.sealImageUrl = '',
    this.materialUrls = '',
    this.reviewStatus = '',
    this.sealStatus = '',
    this.rejectReason,
    this.createTime,
    this.reviewTime,
  });

  final int sealId;
  final String sealName;
  final String sealImageUrl;
  final String materialUrls;
  final String reviewStatus;
  final String sealStatus;
  final String? rejectReason;
  final String? createTime;
  final String? reviewTime;

  /// 审核状态中文标签。
  String get reviewStatusLabel {
    switch (reviewStatus) {
      case 'pending':
        return '审核中';
      case 'approved':
        return '审核通过';
      case 'rejected':
        return '审核驳回';
      default:
        return reviewStatus.isEmpty ? '未知' : reviewStatus;
    }
  }

  /// 印章状态中文标签。
  String get sealStatusLabel {
    switch (sealStatus) {
      case 'enabled':
        return '启用';
      case 'disabled':
        return '停用';
      case 'abnormal':
        return '异常';
      default:
        return sealStatus.isEmpty ? '未知' : sealStatus;
    }
  }

  /// 是否可以重新提交（驳回状态）。
  bool get canResubmit => reviewStatus == 'rejected';

  /// 是否可以停用（启用中即可；含「审核中但仍启用」的异常数据）。
  bool get canDisable => sealStatus == 'enabled';

  /// 启用中须先停用才能提交编辑。
  bool get needsDisableBeforeEdit => sealStatus == 'enabled';

  /// 材料 URL 列表（逗号分隔）。
  List<String> get materialUrlList {
    if (materialUrls.isEmpty) return const <String>[];
    return materialUrls.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  factory SealItem.fromJson(Map<String, dynamic> json) => SealItem(
        sealId: _int(json['sealId']),
        sealName: _text(json['sealName']),
        sealImageUrl: _text(json['sealImageUrl']),
        materialUrls: _text(json['materialUrls']),
        reviewStatus: _text(json['reviewStatus']),
        sealStatus: _text(json['sealStatus']),
        rejectReason: _textOrNull(json['rejectReason']),
        createTime: _textOrNull(json['createTime']),
        reviewTime: _textOrNull(json['reviewTime']),
      );
}

/// 印章详情（含操作日志）。
class SealDetail extends SealItem {
  const SealDetail({
    required super.sealId,
    super.sealName,
    super.sealImageUrl,
    super.materialUrls,
    super.reviewStatus,
    super.sealStatus,
    super.rejectReason,
    super.createTime,
    super.reviewTime,
    this.logs = const <SealLog>[],
  });

  final List<SealLog> logs;

  factory SealDetail.fromJson(Map<String, dynamic> json) {
    final item = SealItem.fromJson(json);
    final logsData = json['logs'];
    final logs = logsData is List
        ? logsData
            .whereType<Map>()
            .map((e) => SealLog.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <SealLog>[];

    return SealDetail(
      sealId: item.sealId,
      sealName: item.sealName,
      sealImageUrl: item.sealImageUrl,
      materialUrls: item.materialUrls,
      reviewStatus: item.reviewStatus,
      sealStatus: item.sealStatus,
      rejectReason: item.rejectReason,
      createTime: item.createTime,
      reviewTime: item.reviewTime,
      logs: logs,
    );
  }
}

/// 印章操作日志。
class SealLog {
  const SealLog({
    required this.logId,
    required this.sealId,
    this.operationType = '',
    this.fromStatus = '',
    this.toStatus = '',
    this.reason,
    this.operatorName = '',
    this.createTime,
  });

  final int logId;
  final int sealId;
  final String operationType;
  final String fromStatus;
  final String toStatus;
  final String? reason;
  final String operatorName;
  final String? createTime;

  /// 操作类型中文标签。
  String get operationTypeLabel {
    switch (operationType) {
      case 'review_approve':
        return '审核通过';
      case 'review_reject':
        return '审核驳回';
      case 'enable':
        return '启用';
      case 'disable':
        return '停用';
      case 'resolve_abnormal':
        return '处理异常';
      default:
        return operationType.isEmpty ? '未知操作' : operationType;
    }
  }

  factory SealLog.fromJson(Map<String, dynamic> json) => SealLog(
        logId: _int(json['logId']),
        sealId: _int(json['sealId']),
        operationType: _text(json['operationType']),
        fromStatus: _text(json['fromStatus']),
        toStatus: _text(json['toStatus']),
        reason: _textOrNull(json['reason']),
        operatorName: _text(json['operatorName']),
        createTime: _textOrNull(json['createTime']),
      );
}
