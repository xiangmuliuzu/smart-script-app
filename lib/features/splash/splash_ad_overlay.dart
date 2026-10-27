import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/app_providers.dart';
import 'splash_ad_image_cache.dart';

class SplashAd {
  const SplashAd(
      {required this.imageUrl,
      required this.durationSeconds,
      this.linkUrl = ''});
  final String imageUrl;
  final String linkUrl;
  final int durationSeconds;
}

final splashAdProvider = FutureProvider<SplashAd?>((ref) async {
  final data = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
        '/ad/splash',
        parser: (raw) =>
            raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
      );
  final image = data?['imageUrl'];
  if (image is! String || image.trim().isEmpty) return null;
  final url = AppConfig.resolveAssetUrl(image.trim());
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) return null;
  final duration = data?['durationSeconds'];
  return SplashAd(
    imageUrl: url,
    linkUrl: data?['linkUrl'] is String ? data!['linkUrl'] as String : '',
    durationSeconds: (duration is num ? duration.toInt() : 5).clamp(1, 10),
  );
});

final splashAdImageCacheProvider = Provider((ref) => SplashAdImageCache());

final splashAdImageProvider = FutureProvider.family<ImageProvider?, String>(
  (ref, url) async {
    final file = await ref.read(splashAdImageCacheProvider).load(url);
    return file == null ? null : FileImage(file);
  },
);

/// 启动最多等待三秒；慢素材继续在后台缓存，为下一次开屏准备。
class SplashAdOverlay extends ConsumerStatefulWidget {
  const SplashAdOverlay({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SplashAdOverlay> createState() => _SplashAdOverlayState();
}

class _SplashAdOverlayState extends ConsumerState<SplashAdOverlay> {
  SplashAd? _ad;
  ImageProvider? _image;
  Timer? _timeout;
  Timer? _countdown;
  int _remaining = 0;
  bool _dismissed = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 3), _dismiss);
    _loadAd();
  }

  Future<void> _loadAd() async {
    try {
      final ad = await ref.read(splashAdProvider.future);
      if (!mounted || _dismissed) return;
      if (ad == null) {
        _dismiss();
        return;
      }
      setState(() {
        _ad = ad;
        _remaining = ad.durationSeconds;
      });
      final image = await ref.read(splashAdImageProvider(ad.imageUrl).future);
      if (!mounted || _dismissed) return;
      if (image == null) {
        _dismiss();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted) _dismiss();
    }
  }

  void _dismiss() {
    if (!mounted || _dismissed) return;
    _timeout?.cancel();
    _countdown?.cancel();
    setState(() => _dismissed = true);
  }

  void _imageReady() {
    if (!mounted || _dismissed || _started) return;
    setState(() => _started = true);
    _timeout?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _dismiss();
        return;
      }
      setState(() => _remaining--);
    });
  }

  Future<void> _openAd() async {
    final uri = Uri.tryParse(_ad?.linkUrl ?? '');
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) return;
    _dismiss();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* 不阻塞启动 */}
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (!_dismissed)
        Positioned.fill(
            child: Material(
          color: const Color(0xfff6f8fb),
          child: Stack(fit: StackFit.expand, children: [
            if (!_started)
              const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('剧云策',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff244a59))),
                SizedBox(height: 16),
                Text('广告加载中…', style: TextStyle(color: Colors.black54)),
              ])),
            if (_image != null)
              GestureDetector(
                onTap: _started ? _openAd : null,
                child: Image(
                  image: _image!,
                  fit: BoxFit.cover,
                  frameBuilder: (context, child, frame, synchronous) {
                    if (frame != null || synchronous) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _imageReady());
                    }
                    return child;
                  },
                  errorBuilder: (context, error, stack) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _dismiss());
                    return const SizedBox.shrink();
                  },
                ),
              ),
            if (_started)
              const Positioned(
                  left: 16,
                  bottom: 24,
                  child: SafeArea(
                      child: Text('广告',
                          style: TextStyle(color: Colors.white, shadows: [
                            Shadow(blurRadius: 4, color: Colors.black)
                          ])))),
            Positioned(
                right: 16,
                top: 8,
                child: SafeArea(
                    child: TextButton(
                  onPressed: _dismiss,
                  style: TextButton.styleFrom(
                      backgroundColor: const Color(0x99000000),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(64, 40)),
                  child:
                      Text(_ad == null || !_started ? '跳过' : '跳过 $_remaining'),
                ))),
          ]),
        )),
    ]);
  }
}
