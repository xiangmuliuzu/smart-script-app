import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:script_app/features/splash/splash_ad_overlay.dart';

Widget app(Future<SplashAd?> Function() load,
        {bool localImage = false,
        ImageProvider? pendingImage,
        Future<ImageProvider?>? imageDownload}) =>
    ProviderScope(
      overrides: [
        splashAdProvider.overrideWith((ref) => load()),
        splashAdImageProvider.overrideWith((ref, url) async {
          if (imageDownload != null) return imageDownload;
          if (pendingImage != null) return pendingImage;
          if (localImage) {
            return const AssetImage('assets/images/logo_script.png');
          }
          return NetworkImage(url);
        })
      ],
      child: const MaterialApp(
        home: SplashAdOverlay(child: Scaffold(body: Text('首页'))),
      ),
    );

class PendingImageProvider extends ImageProvider<PendingImageProvider> {
  @override
  Future<PendingImageProvider> obtainKey(
          ImageConfiguration configuration) async =>
      this;

  @override
  ImageStreamCompleter loadImage(
          PendingImageProvider key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

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

  testWidgets('首帧前保留加载提示，首帧显示后才开始完整倒计时', (tester) async {
    await tester.pumpWidget(app(
        () async => const SplashAd(
              imageUrl: 'https://example.com/large-ad.png',
              durationSeconds: 5,
            ),
        pendingImage: PendingImageProvider()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('剧云策'), findsOneWidget);
    expect(find.text('广告加载中…'), findsOneWidget);
    expect(find.text('广告'), findsNothing);

    final image = tester.widget<Image>(find.byType(Image));
    image.frameBuilder!(
        tester.element(find.byType(Image)), const SizedBox(), 1, false);
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump();
    expect(find.text('广告加载中…'), findsNothing);
    expect(find.text('广告'), findsOneWidget);
    expect(find.text('跳过 5'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('跳过 4'), findsOneWidget);
    await tester.tap(find.text('跳过 4'));
    await tester.pump();
    expect(find.text('跳过 4'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('慢下载三秒后进入首页，迟到图片不会打断用户', (tester) async {
    final download = Completer<ImageProvider?>();
    await tester.pumpWidget(app(
        () async => const SplashAd(
              imageUrl: 'https://example.com/slow-download.png',
              durationSeconds: 5,
            ),
        imageDownload: download.future));
    await tester.pump();
    expect(find.text('广告加载中…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('跳过'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    download.complete(const AssetImage('assets/images/logo_script.png'));
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    expect(find.text('广告'), findsNothing);
  });

  testWidgets('图片解码超时会进入首页，加载中也可立即跳过', (tester) async {
    Future<SplashAd?> load() async => const SplashAd(
          imageUrl: 'https://example.com/hanging-ad.png',
          durationSeconds: 5,
        );
    await tester.pumpWidget(app(load, pendingImage: PendingImageProvider()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('广告加载中…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('跳过'), findsNothing);
    expect(find.text('首页'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(load, pendingImage: PendingImageProvider()));
    await tester.pump();
    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(find.text('广告加载中…'), findsNothing);
    expect(find.text('跳过'), findsNothing);
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
