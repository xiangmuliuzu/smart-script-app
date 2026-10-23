import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/copyright/pages/copyright_certificate_detail_page.dart';
import 'support/scripted_api.dart';

void main() {
  testWidgets('证书下载提示展示服务端链接及实际错误', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/copyright/cert/17', Envelope.ok({
      'certId': 17, 'certNo': 'TEST-17', 'status': 'issued',
    }));
    const url = 'https://example.test/certificate.pdf';
    api.reply('/content/copyright/cert/17/download', Envelope.ok({'url': url}));
    await tester.pumpWidget(ProviderScope(
      overrides: [api.override],
      child: const MaterialApp(home: CopyrightCertificateDetailPage(certId: 17)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下载证书'));
    await tester.pumpAndSettle();
    expect(find.text('证书下载链接：$url'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    api.reply('/content/copyright/cert/17/download', Envelope.fail(40000, '下载暂不可用'));
    await tester.tap(find.byTooltip('下载证书'));
    await tester.pumpAndSettle();
    expect(find.textContaining('下载暂不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
