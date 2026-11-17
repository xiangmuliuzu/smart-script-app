import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/update/data/apk_installer.dart';
import 'package:script_app/features/update/data/app_update_providers.dart';
import 'package:script_app/features/update/data/app_update_repository.dart';
import 'package:script_app/features/update/data/app_version_models.dart';
import 'package:script_app/features/update/widgets/update_dialog.dart';
import 'package:dio/dio.dart';

void main() {
  setUp(() {
    ApkInstaller.debugLocalBuildNumber = 1;
    ApkInstaller.debugDownloadDirectory = null;
  });
  tearDown(() {
    ApkInstaller.debugLocalBuildNumber = null;
    ApkInstaller.debugDownloadDirectory = null;
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('可跳过：普通更新显示「稍后」，点击返回 true', (tester) async {
    var skipped = false;
    await tester.pumpWidget(host(Builder(builder: (context) {
      return TextButton(
        onPressed: () async {
          skipped = await showUpdateDialog(
            context: context,
            prompt: const AppUpdatePrompt(
              info: AppVersionInfo(
                versionCode: 2,
                versionName: '1.0.1',
                minVersionCode: 1,
                url: 'https://example.com/app.apk',
                notes: '修复若干问题',
              ),
              forced: false,
            ),
            repository: AppUpdateRepository(ApiClient(Dio())),
          );
        },
        child: const Text('开'),
      );
    })));

    await tester.tap(find.text('开'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 1.0.1'), findsOneWidget);
    expect(find.textContaining('修复若干问题'), findsOneWidget);
    expect(find.byKey(const Key('app-update-skip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-update-skip')));
    await tester.pumpAndSettle();
    expect(skipped, isTrue);
    expect(find.text('发现新版本 1.0.1'), findsNothing);
  });

  testWidgets('强制更新不提供「稍后」', (tester) async {
    await tester.pumpWidget(host(UpdateDialog(
      prompt: const AppUpdatePrompt(
        info: AppVersionInfo(
          versionCode: 5,
          versionName: '2.0.0',
          minVersionCode: 5,
          url: 'https://example.com/app.apk',
          notes: '',
        ),
        forced: true,
      ),
      repository: AppUpdateRepository(ApiClient(Dio())),
    )));

    expect(find.text('本次更新为必要更新'), findsOneWidget);
    expect(find.byKey(const Key('app-update-skip')), findsNothing);
    expect(find.text('立即更新'), findsOneWidget);
  });
}
