import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/message/data/notification_landing.dart';
import 'package:script_app/features/user_center/data/user_center_models.dart';

MessageItem _tx(String businessType, String? businessId,
        {String source = 'NOTIFICATION', String type = 'TRANSACTION'}) =>
    MessageItem(
      messageId: 7,
      source: source,
      type: type,
      title: '标题',
      businessType: businessType,
      businessId: businessId,
    );

void main() {
  group('通知落点映射', () {
    test('交易域类型直达对应业务页，businessId 即落地页主键', () {
      expect(notificationLandingOf(_tx('INQUIRY', '41'))?.location,
          '${RoutePath.inquiryDetail}?id=41');
      expect(notificationLandingOf(_tx('ORDER', '88'))?.location,
          '${RoutePath.orderDetail}?id=88');
      expect(notificationLandingOf(_tx('DEMAND', '12'))?.location,
          '${RoutePath.demandDetail}?id=12');
    });

    test('合同通知按订单定位签署页，与后端 businessId=orderId 同口径', () {
      expect(notificationLandingOf(_tx('CONTRACT', '88'))?.location,
          '${RoutePath.contractSign}?orderId=88');
    });

    test('提现通知落到提现列表，无需业务主键', () {
      expect(notificationLandingOf(_tx('WITHDRAW', '9'))?.location,
          RoutePath.myIncomeWithdraw);
    });

    test('缺主键、未知类型、公告与非交易消息不产生跳转', () {
      expect(notificationLandingOf(_tx('ORDER', null)), isNull);
      expect(notificationLandingOf(_tx('ORDER', '  ')), isNull);
      expect(notificationLandingOf(_tx('UNKNOWN', '1')), isNull);
      expect(
          notificationLandingOf(
              _tx('ORDER', '88', source: 'ANNOUNCEMENT')),
          isNull);
      expect(
          notificationLandingOf(_tx('ORDER', '88', type: 'SYSTEM')), isNull);
    });

    test('落点带「去处理」文案，供消息详情页按钮复用同一张表', () {
      expect(notificationLandingOf(_tx('ORDER', '88'))?.label, '去处理：查看订单');
      expect(notificationLandingOf(_tx('CONTRACT', '88'))?.label, '去处理：签署合同');
    });
  });
}
