import '../../../core/router/route_paths.dart';
import '../../user_center/data/user_center_models.dart';

/// 站内交易/关注动态/审核通知 → App 业务页落点。
///
/// 同一份映射服务两个入口：系统通知横幅点击后直达业务页（notification_navigation），
/// 消息详情页的「去处理」按钮也走这里，避免两处各写一张表而口径漂移。
///
/// businessType / businessId 由后端统一给出，约定是 **businessId 就是落地页的主键**：
///   - INQUIRY → 询盘 id
///   - ORDER   → 订单 id
///   - CONTRACT→ 订单 id（App 合同页按订单定位，`GET /trade/contracts/{orderId}`）
///   - DEMAND  → 需求 id
///   - WITHDRAW→ 无落点参数，提现列表页本身即是动作页
///   - WORK    → 作品 id（关注动态 type=FOLLOW；审核通过 type=REVIEW）
typedef NotificationLanding = ({String label, String location});

/// 非交易/关注/审核通知、公告，或缺少可定位主键时返回 null（只打开 App，不做跳转）。
NotificationLanding? notificationLandingOf(MessageItem message) {
  if (message.source != 'NOTIFICATION') {
    return null;
  }
  final bizId = (message.businessId ?? '').trim();
  if (message.type == 'FOLLOW') {
    return message.businessType == 'WORK' && bizId.isNotEmpty
        ? (label: '查看作品', location: '${RoutePath.workDetail}?id=$bizId')
        : null;
  }
  // 作品审核通过：打开该作品的工作台，由作者确认后再手动上架，与后端
  // ReviewApprovedNotificationListener 的「不代替作者上架」口径一致。
  if (message.type == 'REVIEW' && message.businessType == 'WORK') {
    final workId = int.tryParse(bizId);
    return workId == null
        ? null
        : (
            label: '去上架：打开作品',
            location: RoutePath.workWorkspaceUrl(workId: workId)
          );
  }
  if (message.type != 'TRANSACTION') {
    return null;
  }
  switch (message.businessType) {
    case 'INQUIRY':
      return bizId.isEmpty
          ? null
          : (
              label: '去处理：查看询盘',
              location: '${RoutePath.inquiryDetail}?id=$bizId'
            );
    case 'ORDER':
      return bizId.isEmpty
          ? null
          : (label: '去处理：查看订单', location: '${RoutePath.orderDetail}?id=$bizId');
    case 'CONTRACT':
      return bizId.isEmpty
          ? null
          : (
              label: '去处理：签署合同',
              location: '${RoutePath.contractSign}?orderId=$bizId'
            );
    case 'DEMAND':
      return bizId.isEmpty
          ? null
          : (label: '去处理：查看任务', location: '${RoutePath.demandDetail}?id=$bizId');
    case 'WITHDRAW':
      return (label: '去处理：查看提现', location: RoutePath.myIncomeWithdraw);
    default:
      return null;
  }
}
