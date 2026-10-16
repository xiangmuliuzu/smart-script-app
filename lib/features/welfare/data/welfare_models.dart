/// 福利中心数据模型（App 端 E 模块）。
///
/// 接口口径（后端 smartscript-review，App 用户侧）：
///   GET  /api/v1/welfare/tasks?userId=             → 任务列表 + 我的进度
///   GET  /api/v1/welfare/points/balance?userId=    → 积分余额
///   GET  /api/v1/welfare/points/records?userId=    → 积分明细
///   GET  /api/v1/ad/list?userId=                   → 广告任务 + 今日已看
///   GET  /api/v1/ai/quota/exchange-records?userId= → 兑换记录
///   POST /api/v1/welfare/task/claim                → 任务领取
///   POST /api/v1/ad/reward                         → 广告奖励
///   POST /api/v1/ai/quota/exchange                 → 积分兑换次数
///
/// 全部为标准若依信封 {code, msg, data}。
library;

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _text(dynamic value) => value == null ? '' : value.toString();

String? _textOrNull(dynamic value) => value?.toString();

/// 福利任务（含我的完成/领取进度）。
class WelfareTask {
  const WelfareTask({
    required this.taskId,
    this.taskName = '',
    this.taskType = '',
    this.taskCode = '',
    this.description = '',
    this.targetCount = 1,
    this.rewardPoints = 0,
    this.icon,
    this.progress = 0,
    this.isCompleted = 0,
    this.isClaimed = 0,
    this.periodDate,
  });

  final int taskId;
  final String taskName;
  final String taskType;
  final String taskCode;
  final String description;
  final int targetCount;
  final int rewardPoints;
  final String? icon;
  final int progress;
  final int isCompleted;
  final int isClaimed;
  final String? periodDate;

  /// 任务类型中文标签。
  String get typeLabel {
    switch (taskType) {
      case 'DAILY':
        return '每日任务';
      case 'AD':
        return '广告任务';
      case 'AI_CREATE':
        return 'AI 创作';
      default:
        return taskType.isEmpty ? '任务' : taskType;
    }
  }

  /// 是否今日可领（每日任务按 periodDate 当天判断，其余按已领取判断）。
  bool get claimable =>
      isClaimed == 0 && (taskType != 'DAILY' || isCompleted >= 1 || progress >= targetCount);

  factory WelfareTask.fromJson(Map<String, dynamic> json) => WelfareTask(
        taskId: _int(json['taskId']),
        taskName: _text(json['taskName']),
        taskType: _text(json['taskType']),
        taskCode: _text(json['taskCode']),
        description: _text(json['description']),
        targetCount: _int(json['targetCount']),
        rewardPoints: _int(json['rewardPoints']),
        icon: _textOrNull(json['icon']),
        progress: _int(json['progress']),
        isCompleted: _int(json['isCompleted']),
        isClaimed: _int(json['isClaimed']),
        periodDate: _textOrNull(json['periodDate']),
      );
}

/// 积分余额。
class PointsBalance {
  const PointsBalance({
    this.balance = 0,
    this.totalEarned = 0,
    this.totalSpent = 0,
    this.todayEarned = 0,
  });

  final int balance;
  final int totalEarned;
  final int totalSpent;
  final int todayEarned;

  factory PointsBalance.fromJson(Map<String, dynamic> json) => PointsBalance(
        balance: _int(json['balance']),
        totalEarned: _int(json['totalEarned']),
        totalSpent: _int(json['totalSpent']),
        todayEarned: _int(json['todayEarned']),
      );
}

/// 积分明细记录。
class PointsRecord {
  const PointsRecord({
    this.recordId = 0,
    this.changeType = '',
    this.points = 0,
    this.balanceAfter = 0,
    this.source = '',
    this.remark = '',
    this.createTime,
  });

  final int recordId;
  final String changeType;
  final int points;
  final int balanceAfter;
  final String source;
  final String remark;
  final String? createTime;

  /// SPEND/consume 为支出（显示负数红色），EARN 为收入。
  bool get isSpend =>
      changeType == 'SPEND' || changeType == 'consume';

  String get signedPoints =>
      isSpend ? '-$points' : (points >= 0 ? '+$points' : '$points');

  factory PointsRecord.fromJson(Map<String, dynamic> json) => PointsRecord(
        recordId: _int(json['recordId']),
        changeType: _text(json['changeType']),
        points: _int(json['points']),
        balanceAfter: _int(json['balanceAfter']),
        source: _text(json['source']),
        remark: _text(json['remark']),
        createTime: _textOrNull(json['createTime']),
      );
}

/// 广告任务（含今日已看次数）。
class AdTask {
  const AdTask({
    required this.adId,
    this.adName = '',
    this.adType = '',
    this.adPosition = '',
    this.rewardPoints = 0,
    this.watchLimit = 0,
    this.dailyCap = 0,
    this.frequencyLimit = 0,
    this.watchedToday = 0,
  });

  final int adId;
  final String adName;
  final String adType;
  final String adPosition;
  final int rewardPoints;
  final int watchLimit;
  final int dailyCap;
  final int frequencyLimit;
  final int watchedToday;

  /// 广告类型中文标签。
  String get typeLabel {
    switch (adType) {
      case 'splash':
        return '开屏';
      case 'interstitial':
        return '插屏';
      case 'reward':
        return '激励视频';
      case 'banner':
        return 'Banner';
      default:
        return adType.isEmpty ? '广告' : adType;
    }
  }

  /// 今日还可观看次数（watchLimit - watchedToday，不小于 0）。
  int get remainingToday => (watchLimit - watchedToday) < 0 ? 0 : watchLimit - watchedToday;

  factory AdTask.fromJson(Map<String, dynamic> json) => AdTask(
        adId: _int(json['adId']),
        adName: _text(json['adName']),
        adType: _text(json['adType']),
        adPosition: _text(json['adPosition']),
        rewardPoints: _int(json['rewardPoints']),
        watchLimit: _int(json['watchLimit']),
        dailyCap: _int(json['dailyCap']),
        frequencyLimit: _int(json['frequencyLimit']),
        watchedToday: _int(json['watchedToday']),
      );
}

/// 积分兑换 AI 次数记录。
class ExchangeRecord {
  const ExchangeRecord({
    this.recordId = 0,
    this.type = '',
    this.businessType = '',
    this.amount = 0,
    this.balanceAfter = 0,
    this.remark = '',
    this.createTime,
  });

  final int recordId;
  final String type;
  final String businessType;
  final int amount;
  final int balanceAfter;
  final String remark;
  final String? createTime;

  /// 兑换获得 AI 次数（exchange 流水 amount 为获得的次数）。
  int get spentPoints => amount;

  factory ExchangeRecord.fromJson(Map<String, dynamic> json) => ExchangeRecord(
        recordId: _int(json['recordId']),
        type: _text(json['type']),
        businessType: _text(json['businessType']),
        amount: _int(json['amount']),
        balanceAfter: _int(json['balanceAfter']),
        remark: _text(json['remark']),
        createTime: _textOrNull(json['createTime']),
      );
}
