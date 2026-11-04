/// 作品推广（付费推荐）数据模型。
///
/// 字段与后端 `/api/v1/content/promotion` 契约一一对应：
///   - [PromotionSlotPage] ← GET /promotion/slots
///   - [PromotionApplication] ← POST /promotion/applications、列表、详情
///   - 支付 ← /trade/promotion/{applyId}/pay、/confirm
library;

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int _toInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _toIntOrNull(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String && value.isNotEmpty) return int.tryParse(value);
  return null;
}

bool _toBool(dynamic value) =>
    value == '1' || value == 1 || value == true || value == 'true';

String _toText(dynamic value) => value == null ? '' : value.toString();

String? _toTextOrNull(dynamic value) => value?.toString();

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value.replaceFirst(' ', 'T'));
}

/// 资源位总览（当前用户视角只关心空闲 / 锁坑 / 投放）。
class PromotionOverview {
  const PromotionOverview({
    this.totalSlots = 0,
    this.activeCount = 0,
    this.lockedCount = 0,
    this.idleCount = 0,
    this.pendingCount = 0,
  });

  final int totalSlots;
  final int activeCount;
  final int lockedCount;
  final int idleCount;
  final int pendingCount;

  factory PromotionOverview.fromJson(Map<String, dynamic> json) =>
      PromotionOverview(
        totalSlots: _toInt(json['totalSlots']),
        activeCount: _toInt(json['activeCount']),
        lockedCount: _toInt(json['lockedCount']),
        idleCount: _toInt(json['idleCount']),
        pendingCount: _toInt(json['pendingCount']),
      );
}

/// 推广申请 / 投放记录。
class PromotionApplication {
  const PromotionApplication({
    required this.applyId,
    this.applyNo = '',
    this.workId = 0,
    this.slotType = '',
    this.slotNo = 0,
    this.startTime,
    this.endTime,
    this.days = 0,
    this.amount = 0,
    this.status = '',
    this.payStatus = '',
    this.lockExpireAt,
    this.statusLabel = '',
    this.lockRemainSeconds,
    this.rejectReason,
    this.workTitle = '',
    this.workCover,
    this.authorName = '',
    this.source = '',
    this.materialUrl,
    this.createTime,
    this.payTime,
  });

  final int applyId;
  final String applyNo;
  final int workId;
  final String slotType;
  final int slotNo;
  final String? startTime;
  final String? endTime;
  final int days;
  final double amount;
  final String status;
  final String payStatus;
  final String? lockExpireAt;

  /// 后端派生状态文案（待审核 / 待支付 / 待生效 / 投放中 / 已结束 / 已驳回 / 已取消 / 已失效）。
  final String statusLabel;
  final int? lockRemainSeconds;
  final String? rejectReason;
  final String workTitle;
  final String? workCover;
  final String authorName;
  final String source;

  /// 作者申请轮播推广时提交的素材地址（仅 banner 有值）。
  final String? materialUrl;
  final String? createTime;
  final String? payTime;

  factory PromotionApplication.fromJson(Map<String, dynamic> json) =>
      PromotionApplication(
        applyId: _toInt(json['applyId']),
        applyNo: _toText(json['applyNo']),
        workId: _toInt(json['workId']),
        slotType: _toText(json['slotType']),
        slotNo: _toInt(json['slotNo']),
        startTime: _toTextOrNull(json['startTime']),
        endTime: _toTextOrNull(json['endTime']),
        days: _toInt(json['days']),
        amount: _toDouble(json['amount']),
        status: _toText(json['status']),
        payStatus: _toText(json['payStatus']),
        lockExpireAt: _toTextOrNull(json['lockExpireAt']),
        statusLabel: _toText(json['statusLabel']),
        lockRemainSeconds: _toIntOrNull(json['lockRemainSeconds']),
        rejectReason: _toTextOrNull(json['rejectReason']),
        workTitle: _toText(json['workTitle']),
        workCover: _toTextOrNull(json['workCover']),
        authorName: _toText(json['authorName']),
        source: _toText(json['source']),
        materialUrl: _toTextOrNull(json['materialUrl']),
        createTime: _toTextOrNull(json['createTime']),
        payTime: _toTextOrNull(json['payTime']),
      );

  String get slotTypeLabel {
    switch (slotType) {
      case 'hot':
        return '首页热门精选';
      case 'search':
        return '搜索推荐';
      case 'banner':
        return '首页轮播';
      default:
        return slotType;
    }
  }

  String get slotLabel => '$slotTypeLabel · 第$slotNo位';

  String get sourceLabel => source == 'admin_grant' ? '官方赠送' : '付费推广';

  /// 列表接口也下发 statusLabel；本地再兜底一次，避免字段缺失时展示空白。
  String get displayStatus {
    if (statusLabel.isNotEmpty) return statusLabel;
    switch (status) {
      case 'pending':
        return '待审核';
      case 'rejected':
        return '已驳回';
      case 'cancelled':
        return '已取消';
      case 'approved':
        if (payStatus == 'unpaid') {
          final remain = lockRemainSecondsValue;
          return (remain == null || remain <= 0) ? '已失效' : '待支付';
        }
        break;
      case 'paid':
        final start = _parseDate(startTime);
        final end = _parseDate(endTime);
        final now = DateTime.now();
        if (start != null && start.isAfter(now)) return '待生效';
        if (end != null && end.isBefore(now)) return '已结束';
        return '投放中';
    }
    return '未知状态';
  }

  /// 锁坑剩余秒数：优先按 lockExpireAt 实时计算，缺失时用后端下发值兜底。
  int? get lockRemainSecondsValue {
    final expire = _parseDate(lockExpireAt);
    if (expire != null) {
      final diff = expire.difference(DateTime.now()).inSeconds;
      return diff > 0 ? diff : 0;
    }
    return lockRemainSeconds;
  }

  /// 锁坑倒计时文案（不足 1 秒 / 已过期返回 null）。
  String? get lockRemainText {
    final seconds = lockRemainSecondsValue;
    if (seconds == null || seconds <= 0) return null;
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  bool get canPay =>
      status == 'approved' &&
      payStatus == 'unpaid' &&
      (lockRemainSecondsValue ?? 0) > 0;

  bool get canCancel =>
      status == 'pending' || (status == 'approved' && payStatus == 'unpaid');
}

/// 单个推广位次。
class PromotionSlotItem {
  const PromotionSlotItem({
    required this.slotId,
    this.slotType = '',
    this.slotNo = 0,
    this.pricePerDay = 0,
    this.enabled = false,
    this.state = '',
    this.remark,
    this.current,
    this.next,
    this.bannerTitle = '',
  });

  final int slotId;
  final String slotType;
  final int slotNo;
  final double pricePerDay;
  final bool enabled;

  /// idle / locked / active / reserved / missing_material / disabled
  final String state;
  final String? remark;
  final PromotionApplication? current;
  final PromotionApplication? next;

  /// 同序位运营素材标题（付费申请未生效时的兜底展示）。
  final String bannerTitle;

  factory PromotionSlotItem.fromJson(Map<String, dynamic> json) =>
      PromotionSlotItem(
        slotId: _toInt(json['slotId']),
        slotType: _toText(json['slotType']),
        slotNo: _toInt(json['slotNo']),
        pricePerDay: _toDouble(json['pricePerDay']),
        enabled: _toBool(json['enabled']),
        state: _toText(json['state']),
        remark: _toTextOrNull(json['remark']),
        current: json['current'] is Map
            ? PromotionApplication.fromJson(
                Map<String, dynamic>.from(json['current'] as Map))
            : null,
        next: json['next'] is Map
            ? PromotionApplication.fromJson(
                Map<String, dynamic>.from(json['next'] as Map))
            : null,
        bannerTitle: json['banner'] is Map
            ? _toText((json['banner'] as Map)['title'])
            : '',
      );

  String get stateLabel {
    switch (state) {
      case 'idle':
        return '空闲';
      case 'locked':
        return '待支付';
      case 'active':
        return '投放中';
      case 'reserved':
        return '已预约';
      case 'missing_material':
        return '待补素材';
      case 'disabled':
        return '已停用';
      default:
        return state;
    }
  }

  /// 可预约：启用且空闲；轮播位若只有后台默认素材（current 为空）仍可购买。
  bool get selectable =>
      enabled && (state == 'idle' || (state == 'active' && current == null));

  /// 位次副标题：优先展示当前投放作品，其次展示备注。
  String get subtitle {
    if (!enabled) return '该位次已停用';
    final title = current?.workTitle ?? '';
    if (title.isNotEmpty) return '当前：$title';
    if (current != null) return current!.displayStatus;
    if (bannerTitle.isNotEmpty) return '运营素材：$bannerTitle';
    final note = remark ?? '';
    if (note.isNotEmpty) return note;
    return stateLabel;
  }
}

/// 资源位位次列表 + 总览。
class PromotionSlotPage {
  const PromotionSlotPage({
    required this.slotType,
    this.overview,
    this.slots = const [],
  });

  final String slotType;
  final PromotionOverview? overview;
  final List<PromotionSlotItem> slots;

  factory PromotionSlotPage.fromJson(
      Map<String, dynamic> json, String fallbackType) {
    final rawSlots = json['slots'];
    return PromotionSlotPage(
      slotType: _toText(json['slotType']).isEmpty
          ? fallbackType
          : _toText(json['slotType']),
      overview: json['overview'] is Map
          ? PromotionOverview.fromJson(
              Map<String, dynamic>.from(json['overview'] as Map))
          : null,
      slots: rawSlots is List
          ? rawSlots
              .whereType<Map>()
              .map((e) =>
                  PromotionSlotItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  PromotionSlotItem? slotByNo(int? slotNo) {
    if (slotNo == null) return null;
    for (final slot in slots) {
      if (slot.slotNo == slotNo) return slot;
    }
    return null;
  }
}

/// 创建支付返回：支付宝沙箱收款二维码。
class PromotionPaymentOrder {
  const PromotionPaymentOrder({required this.qrCode, this.sandbox = false});

  final String qrCode;
  final bool sandbox;

  factory PromotionPaymentOrder.fromJson(Map<String, dynamic> json) =>
      PromotionPaymentOrder(
        qrCode: _toText(json['qrCode']),
        sandbox: _toBool(json['sandbox']),
      );
}

/// 查询支付结果。
class PromotionPaymentConfirm {
  const PromotionPaymentConfirm(
      {this.paid = false, this.closed = false, this.sandbox = false});

  final bool paid;
  final bool closed;
  final bool sandbox;

  factory PromotionPaymentConfirm.fromJson(Map<String, dynamic> json) =>
      PromotionPaymentConfirm(
        paid: _toBool(json['paid']),
        closed: _toBool(json['closed']),
        sandbox: _toBool(json['sandbox']),
      );
}
