import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/theme/app_theme.dart';
import 'package:script_app/features/trade/widgets/demand_sandbox_pay_dialog.dart';

/// 沙箱收款弹窗在真机尺寸（411.4x890.3 逻辑像素）下必须可见，且支持换新收款码。
void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Future<Map<String, dynamic>> Function() confirm,
    required Future<Map<String, dynamic>> Function() onRefresh,
  }) async {
    // 模拟器实测逻辑尺寸 411.4x890.3（1080px / dpr 2.625）：此宽度下 AlertDialog 会去量内容的
    // 固有宽度，内容里出现 LayoutBuilder（如 QrImageView）会抛异常并中断布局，弹窗只剩一层黑幕。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(builder: (ctx) {
        return ElevatedButton(
          onPressed: () {
            showDialog<bool>(
              context: ctx,
              builder: (_) => DemandSandboxPayDialog(
                title: '支付押金',
                qrCode: 'https://openapi-sandbox.dl.alipaydev.com/gateway.do?method=alipay.trade.precreate',
                amountYuanText: '20.00',
                hint: '支付押金即视为接单成功（沙箱收款）。逾期未验收通过，押金将被没收。',
                confirm: confirm,
                onRefresh: onRefresh,
              ),
            );
          },
          child: const Text('go'),
        );
      }),
    ));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('沙箱收款弹窗在真机尺寸下可见', (tester) async {
    await pumpDialog(
      tester,
      confirm: () async => <String, dynamic>{'paid': false},
      onRefresh: () async => <String, dynamic>{'qrCode': 'https://new-code'},
    );

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('支付押金')).width, greaterThan(0));
    expect(tester.getRect(find.text('金额 ¥20.00')).width, greaterThan(0));
    expect(tester.getRect(find.text('刷新二维码')).width, greaterThan(0));
    expect(tester.getRect(find.text('关闭')).width, greaterThan(0));
    await expectLater(find.byType(AlertDialog),
        matchesGoldenFile('sandbox_pay_dialog.png'));
  });

  testWidgets('点刷新二维码会向服务端换新码', (tester) async {
    var refreshCalls = 0;
    final pending = Completer<Map<String, dynamic>>();
    await pumpDialog(
      tester,
      confirm: () async => <String, dynamic>{'paid': false},
      onRefresh: () {
        refreshCalls++;
        return pending.future;
      },
    );

    await tester.tap(find.text('刷新二维码'));
    await tester.pump();
    expect(refreshCalls, 1);
    expect(find.text('正在生成新的收款码…'), findsOneWidget);
    expect(find.text('刷新二维码'), findsNothing);

    pending.complete(<String, dynamic>{'qrCode': 'https://new-code'});
    await tester.pump();
    // 换码成功后恢复默认提示，按钮重新可点
    expect(find.text('等待支付结果…扫码完成后会自动确认'), findsOneWidget);
    expect(find.text('刷新二维码'), findsOneWidget);
  });

  testWidgets('支付宝侧旧单已关闭时自动换新码', (tester) async {
    var refreshCalls = 0;
    await pumpDialog(
      tester,
      confirm: () async => <String, dynamic>{'paid': false, 'closed': true},
      onRefresh: () async {
        refreshCalls++;
        return <String, dynamic>{'qrCode': 'https://new-code'};
      },
    );

    // 弹窗每 3 秒查单一次，查得 closed 后应自动发起换码
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(refreshCalls, 1);
  });

  testWidgets('服务端查明旧码其实已付款时按成功收尾', (tester) async {
    await pumpDialog(
      tester,
      confirm: () async => <String, dynamic>{'paid': false},
      onRefresh: () async => <String, dynamic>{'paid': true},
    );

    await tester.tap(find.text('刷新二维码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
  });
}
