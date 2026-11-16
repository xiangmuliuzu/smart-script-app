import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../data/qr_login_models.dart';

/// 扫一扫：识别网页登录二维码，交给 [QrConfirmPage] 让用户确认。
///
/// 只在本进程内取第一帧有效码：识别到之后立刻停扫并进入确认页，
/// 避免同一张码被连续触发、或在确认页返回后又被扫一次。
class QrScanPage extends ConsumerStatefulWidget {
  const QrScanPage({super.key});

  @override
  ConsumerState<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends ConsumerState<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => parseQrLoginToken(value) != null, orElse: () => '');
    if (raw.isEmpty) return;
    final token = parseQrLoginToken(raw);
    if (token == null) return;

    setState(() => _handling = true);
    await _controller.stop();
    try {
      // 先登记「这张票是我扫的」，再把登录端与浏览器信息带去确认页。
      // 登记失败（过期、已被扫过）就在本页提示，不进入确认页。
      final target = await ref.read(authRepositoryProvider).scanQrLogin(token);
      if (!mounted) return;
      final confirmed = await context.push<bool>(
        '${RoutePath.qrConfirm}?t=${Uri.encodeComponent(token)}',
        extra: target,
      );
      if (!mounted) return;
      if (confirmed == true) {
        // 已确认：网页那边会自行取走登录态，这里回到扫一扫的入口。
        context.pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('扫码失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _handling = false);
        // 用户从确认页返回（取消 / 失败）时恢复取景，可以直接重扫。
        try {
          await _controller.start();
        } catch (_) {
          // 相机未就绪（如权限被收回）时保持停帧，页面提示仍可见。
        }
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫一扫'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 44),
                    const SizedBox(height: 14),
                    Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? '没有相机权限，请在系统设置中允许访问相机后重试'
                          : '相机暂时不可用，请稍后重试',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 取景框：只做视觉引导，识别仍是整幅画面（服务端才是真正的校验方）。
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.card, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 56),
              child: Text(
                _handling ? '正在识别…' : '将网页上的登录二维码放入框内',
                style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.6),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
