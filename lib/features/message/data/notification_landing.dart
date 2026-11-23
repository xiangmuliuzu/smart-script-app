import '../../../core/router/route_paths.dart';
import '../../user_center/data/user_center_models.dart';

/// 站内通知 → App 业务页落点。
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
///   - WORK    → 作品 id（关注动态 type=FOLLOW；审核通过通知已并入 SYSTEM）
///   - SEAL    → 印章 id
///   - COPYRIGHT_APPLY → 版权申请 id
///   - COPYRIGHT_CERT  → 证书 id
typedef NotificationLanding = ({String label, String location});

/// 非业务通知、公告，或缺少可定位主键时返回 null（只打开 App，不做跳转）。
NotificationLanding? notificationLandingOf(MessageItem message) {
  if (message.source != 'NOTIFICATION') {
    return null;
  }
  final bizId = (message.businessId ?? '').trim();
  // 作品业务引用：关注动态打开作品详情；审核通过通知（审核分类已并入系统）打开
  // 作品工作台，由作者确认后再手动上架，与后端 ReviewApprovedNotificationListener 一致。
  if (message.businessType == 'WORK' && bizId.isNotEmpty) {
    if (message.type == 'FOLLOW') {
      return (label: '查看作品', location: '${RoutePath.workDetail}?id=$bizId');
    }
    if (message.type == 'SYSTEM' || message.type == 'REVIEW') {
      final workId = int.tryParse(bizId);
      return workId == null
          ? null
          : (
              label: '去上架：打开作品',
              location: RoutePath.workWorkspaceUrl(workId: workId)
            );
    }
  }
  // 印章 / 版权：独立消息类型，落点按 businessType
  if (message.type == 'SEAL' || message.businessType == 'SEAL') {
    final sealId = int.tryParse(bizId);
    return sealId == null
        ? null
        : (label: '查看印章', location: RoutePath.sealDetailUrl(sealId));
  }
  if (message.type == 'COPYRIGHT' ||
      message.businessType == 'COPYRIGHT_APPLY' ||
      message.businessType == 'COPYRIGHT_CERT') {
    switch (message.businessType) {
      case 'COPYRIGHT_CERT':
        final certId = int.tryParse(bizId);
        return certId == null
            ? null
            : (
                label: '查看证书',
                location: RoutePath.copyrightCertificateDetailUrl(certId)
              );
      case 'COPYRIGHT_APPLY':
      default:
        final applyId = int.tryParse(bizId);
        return applyId == null
            ? null
            : (
                label: '查看申请',
                location: RoutePath.copyrightApplicationDetailUrl(applyId)
              );
    }
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
