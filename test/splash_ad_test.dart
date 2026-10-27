import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:script_app/features/splash/splash_ad_overlay.dart';

Widget app(Future<SplashAd?> Function() load, {bool localImage = false}) =>
    ProviderScope(
      overrides: [
        splashAdProvider.overrideWith((ref) => load()),
        if (localImage)
          splashAdImageProvider.overrideWith(
              (ref, url) => const AssetImage('assets/images/logo_script.png'))
      ],
      child: const MaterialApp(
        home: SplashAdOverlay(child: Scaffold(body: Text('首页'))),
      ),
    );

void main() {
  testWidgets('没有广告或请求失败时进入首页', (tester) async {
    await tester.pumpWidget(app(() async => null));
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(() async => throw Exception('offline')));
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
  });

  testWidgets('可立即跳过，迟到的请求不会重新展示广告', (tester) async {
    final result = Completer<SplashAd?>();
    await tester.pumpWidget(app(() => result.future));
    expect(find.text('跳过'), findsOneWidget);
    await tester.tap(find.text('跳过'));
    await tester.pump();
    result.complete(const SplashAd(
        imageUrl: 'https://example.com/ad.png', durationSeconds: 5));
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('请求超时不会挡住首页', (tester) async {
    final result = Completer<SplashAd?>();
    await tester.pumpWidget(app(() => result.future));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('跳过'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    result.complete(null);
    await tester.pump();
  });

  testWidgets('图片加载失败时进入首页', (tester) async {
    await tester.pumpWidget(app(() async => const SplashAd(
          imageUrl: 'https://example.com/missing.png',
          durationSeconds: 5,
        )));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });
  testWidgets('图片就绪后倒计时结束自动进入首页', (tester) async {
    await tester.pumpWidget(app(
        () async => const SplashAd(
              imageUrl: 'https://example.com/ad.png',
              durationSeconds: 2,
            ),
        localImage: true));
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    image.frameBuilder!(
        tester.element(find.byType(Image)), const SizedBox(), 1, false);
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('跳过 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('跳过 1'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });
}
