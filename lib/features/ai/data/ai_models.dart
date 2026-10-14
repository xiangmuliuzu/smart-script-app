import 'dart:convert';

/// AI 创作模块数据模型（App 端 E 模块）。
///
/// 接口口径（后端 smartscript-review）：
///   GET  /api/v1/ai/quota/balance?userId=   → 余额 + 最近流水
///   POST /api/v1/ai/quota/consume          → 消耗（预扣，幂等）
///   POST /api/v1/ai/quota/refund           → 失败补偿（幂等）
///   POST /api/v1/ai/quota/exchange         → 积分兑换次数（幂等）
///   POST /api/v1/ai/quota/reserve/confirm/release → 预留锁定两段式
///
/// 后端已统一返回标准若依信封 {code, msg, data}。

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _text(dynamic value) => value == null ? '' : value.toString();

/// AI 机会余额（data 字段，宽容解析）。
class AiQuotaBalance {
  const AiQuotaBalance({
    this.available = 0,
    this.reserved = 0,
    this.totalEarned = 0,
    this.totalConsumed = 0,
    this.totalRefunded = 0,
    this.rate = 10,
    this.records = const [],
  });

  /// 可用次数。
  final int available;

  /// 预留（任务进行中锁定）次数。
  final int reserved;

  /// 累计获得。
  final int totalEarned;

  /// 累计消耗。
  final int totalConsumed;

  /// 累计失败补偿。
  final int totalRefunded;

  /// 最近流水（AI 机会记录）。
  final List<AiQuotaRecord> records;

  /// 积分兑换 AI 次数比例（10 积分 = 1 次；管理员可在管理端调整，实时生效）。
  final int rate;

  bool get hasAccount =>
      totalEarned > 0 || totalConsumed > 0 || available > 0;

  factory AiQuotaBalance.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'] ?? json['list'];
    return AiQuotaBalance(
      available: _int(json['availableQuota'] ?? json['available']),
      reserved: _int(json['reservedQuota'] ?? json['reserved']),
      totalEarned: _int(json['totalEarned']),
      totalConsumed: _int(json['totalConsumed']),
      totalRefunded: _int(json['totalRefunded']),
      rate: _int(json['rate'] ?? 10),
      records: rawRecords is List
          ? rawRecords
              .map((e) => AiQuotaRecord.fromJson(
                  e is Map ? Map<String, dynamic>.from(e) : const {}))
              .toList()
          : const [],
    );
  }
}

/// AI 机会流水（消耗 / 获得 / 补偿 / 兑换）。
class AiQuotaRecord {
  const AiQuotaRecord({
    this.changeType = '',
    this.changeAmount = 0,
    this.balanceAfter = 0,
    this.businessType = '',
    this.source = '',
    this.remark = '',
    this.createTime,
  });

  /// 后端 type（小写：consume/refund/earn/reserve/confirm/release）。
  final String changeType;
  final int changeAmount;
  final int balanceAfter;
  final String businessType;
  final String source;
  final String remark;
  final String? createTime;

  /// 是否为「扣减」类（消耗 / 确认消耗）。
  bool get isOutgoing => changeType == 'consume' || changeType == 'confirm';

  /// 变化类型中文标签。
  String get typeLabel {
    switch (changeType) {
      case 'consume':
        return '消耗';
      case 'refund':
        return '失败补偿';
      case 'earn':
        return '兑换获得';
      case 'reserve':
        return '预留锁定';
      case 'confirm':
        return '确认消耗';
      case 'release':
        return '释放回补';
      default:
        return changeType.isEmpty ? '记录' : changeType;
    }
  }

  /// 正负符号展示（获得为 +，消耗为 -）。
  String get signedAmount =>
      isOutgoing ? '-$changeAmount' : '+$changeAmount';

  factory AiQuotaRecord.fromJson(Map<String, dynamic> json) => AiQuotaRecord(
        changeType: _text(json['changeType'] ?? json['type']),
        changeAmount: _int(json['changeAmount'] ?? json['amount']),
        balanceAfter: _int(
            json['balanceAfter'] ?? json['balance'] ?? json['afterBalance']),
        businessType: _text(json['businessType']),
        source: _text(json['source']),
        remark: _text(json['remark']),
        createTime: json['createTime']?.toString(),
      );
}

// ================================================================
// AI 创作（大纲/写作/润色）结果模型（对接 /api/v1/content/ai/*）
// ================================================================

/// AI 写作 / 润色结果（data：{content, recordId}）。
class AiWriteResult {
  const AiWriteResult({this.content = '', this.recordId = 0});

  final String content;
  final int recordId;

  factory AiWriteResult.fromJson(Map<String, dynamic> json) => AiWriteResult(
        content: _text(json['content']),
        recordId: _int(json['recordId']),
      );
}

/// AI 大纲生成结果（data：{outline, requestNo, quotaUsed}）。
///
/// outline 为 AI 返回的对象（结构因服务商而异），不做二次建模。
class AiOutlineResult {
  const AiOutlineResult({
    this.outline,
    this.requestNo = '',
    this.quotaUsed = 0,
  });

  final dynamic outline;
  final String requestNo;
  final int quotaUsed;

  /// 大纲是否有内容。
  bool get hasOutline => outline != null && '$outline'.trim().isNotEmpty;

  /// 把大纲转为可读文本（对象时按 JSON 缩进展示）。
  String get outlineText {
    if (outline == null) return '';
    if (outline is String) return outline as String;
    try {
      return _prettyJson(outline);
    } catch (_) {
      return outline.toString();
    }
  }

  factory AiOutlineResult.fromJson(Map<String, dynamic> json) =>
      AiOutlineResult(
        outline: json['outline'],
        requestNo: _text(json['requestNo']),
        quotaUsed: _int(json['quotaUsed']),
      );
}

/// AI 写作记录项（write-records 列表元素）。
class AiWriteRecord {
  const AiWriteRecord({
    this.recordId = 0,
    this.title = '',
    this.writeType = '',
    this.inputPrompt = '',
    this.outputContent = '',
    this.wordCount = 0,
    this.aiModel = '',
    this.status = '',
    this.createdAt = '',
  });

  final int recordId;
  final String title;
  final String writeType;
  final String inputPrompt;
  final String outputContent;
  final int wordCount;
  final String aiModel;
  final String status;
  final String createdAt;

  /// 写作类型中文标签。
  String get writeTypeLabel {
    switch (writeType) {
      case 'write':
        return 'AI 写作';
      case 'polish':
        return 'AI 润色';
      case 'outline':
        return 'AI 大纲';
      default:
        return writeType.isEmpty ? '记录' : writeType;
    }
  }

  factory AiWriteRecord.fromJson(Map<String, dynamic> json) => AiWriteRecord(
        recordId: _int(json['recordId']),
        title: _text(json['title']),
        writeType: _text(json['writeType']),
        inputPrompt: _text(json['inputPrompt']),
        outputContent: _text(json['outputContent']),
        wordCount: _int(json['wordCount']),
        aiModel: _text(json['aiModel']),
        status: _text(json['status']),
        createdAt: _text(json['createdAt'] ?? json['createTime']),
      );
}


/// 分页结果（{total, list}）的通用解析。
class AiPageResult<T> {
  const AiPageResult({this.total = 0, this.list = const []});

  final int total;
  final List<T> list;

  factory AiPageResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) itemBuilder,
  ) {
    final rawList = json['list'] ?? json['rows'];
    return AiPageResult<T>(
      total: _int(json['total']),
      list: rawList is List
          ? rawList
              .map((e) => itemBuilder(
                  e is Map ? Map<String, dynamic>.from(e) : const {}))
              .toList()
          : const [],
    );
  }
}

String _prettyJson(dynamic value) {
  // 轻量 JSON 缩进（避免引入额外依赖时的格式问题）
  return const JsonEncoder.withIndent('  ').convert(value);
}
