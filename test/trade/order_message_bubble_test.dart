import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/features/chat/data/chat_models.dart';
import 'package:script_app/features/chat/widgets/order_message_bubble.dart';

ChatMessage _sysMsg(String content) => ChatMessage(
      messageId: 1,
      sessionId: 2,
      senderId: 0,
      content: content,
      msgType: 'SYSTEM',
    );

void main() {
  group('OrderMessageBubble 载荷解析', () {
    test('识别 [订单] 前缀并解析 orderId/orderNo', () {
      final msg = _sysMsg('[订单]{"orderId":9612,"orderNo":"ORD20261102140711A005"}');
      expect(OrderMessageBubble.isOrderMessage(msg), isTrue);
      final payload = OrderMessageBubble.parse(msg);
      expect(payload?.orderId, 9612);
      expect(payload?.orderNo, 'ORD20261102140711A005');
    });

    test('JSON 非法不渲染卡片', () {
      final msg = _sysMsg('[订单]{不是json');
      expect(OrderMessageBubble.isOrderMessage(msg), isTrue);
      expect(OrderMessageBubble.parse(msg), isNull);
    });

    test('缺 orderId 不渲染卡片', () {
      final msg = _sysMsg('[订单]{"orderNo":"ORD1"}');
      expect(OrderMessageBubble.parse(msg), isNull);
    });

    test('非 SYSTEM 或非 [订单] 前缀不识别', () {
      expect(
        OrderMessageBubble.isOrderMessage(
            _sysMsg('[报价] 卖方报价 ¥1.00 | 独家授权')),
        isFalse,
      );
      expect(
        OrderMessageBubble.isOrderMessage(const ChatMessage(
            messageId: 1,
            sessionId: 2,
            senderId: 3,
            content: '[订单]{"orderId":1}',
            msgType: 'TEXT')),
        isFalse,
      );
    });
  });
}
