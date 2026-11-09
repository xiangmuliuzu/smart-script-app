import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/copyright/data/certificate_download_helper.dart';
import 'package:script_app/features/copyright/pages/copyright_certificate_detail_page.dart';
import 'support/scripted_api.dart';

class _InstantDownloadHelper extends CertificateDownloadHelper {
  _InstantDownloadHelper(this.file)
      : super(documentsDirectory: () async => file.parent);

  final File file;

  @override
  Future<File> saveCertificatePdf({
    required String url,
    required String fileName,
    String? certNo,
    String? workName,
  }) {
    file.writeAsBytesSync(
      CertificateDownloadHelper.buildMockCertPdf(
        certNo: certNo,
        workName: workName,
      ),
    );
    return Future<File>.value(file);
  }
}

void main() {
  late Directory tempDir;
  late File savedFile;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('cert_dl_');
    savedFile = File('${tempDir.path}/证书_TEST-17.pdf');
    CertificateDownloadHelper.debugOverride = _InstantDownloadHelper(savedFile);
    CertificateDownloadHelper.debugOpenFile = (_) async => false;
  });

  tearDown(() async {
    CertificateDownloadHelper.debugOverride = null;
    CertificateDownloadHelper.debugOpenFile = null;
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  testWidgets('证书下载保存本地文件并展示成功提示', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/copyright/cert/17', Envelope.ok({
      'certId': 17,
      'certNo': 'TEST-17',
      'status': 'issued',
      'workName': '测试作品',
    }));
    const url = 'https://mock-cert.example.com/cert.pdf';
    api.reply('/content/copyright/cert/17/download', Envelope.ok({'url': url}));
    await tester.pumpWidget(ProviderScope(
      overrides: [api.override],
      child: const MaterialApp(home: CopyrightCertificateDetailPage(certId: 17)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下载证书'));
    await tester.pumpAndSettle();

    expect(find.textContaining('证书已'), findsOneWidget);
    expect(find.text('证书下载链接：$url'), findsNothing);
    expect(savedFile.existsSync(), isTrue);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    api.reply('/content/copyright/cert/17/download', Envelope.fail(40000, '下载暂不可用'));
    await tester.tap(find.byTooltip('下载证书'));
    await tester.pumpAndSettle();
    expect(find.textContaining('下载暂不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('mock 链接回退生成本地 PDF 字节', () async {
    final helper = CertificateDownloadHelper(
      documentsDirectory: () async => tempDir,
    );
    final bytes = await helper.resolvePdfBytes(
      url: 'https://mock-cert.example.com/cert.pdf',
      certNo: 'CERT-1',
      workName: '作品A',
    );
    expect(bytes.length, greaterThan(20));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
