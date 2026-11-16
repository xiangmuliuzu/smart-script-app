import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_page_background.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/qr_login_models.dart';

/// 扫码后的登录确认页。
///
/// 这是整个扫码登录唯一的「人」的关口：必须让用户看清**站点 + 浏览器**，
/// 并默认把焦点放在确认之外的操作上（返回即取消），避免误触把账号登进别人电脑。
class QrConfirmPage extends ConsumerStatefulWidget {
  const QrConfirmPage({super.key, required this.qrToken, this.target});

  final String qrToken;

  /// 扫描接口已返回的登录端信息；为空时按创作者端兜底展示。
  final QrScanTarget? target;

  @override
  ConsumerState<QrConfirmPage> createState() => _QrConfirmPageState();
}

class _QrConfirmPageState extends ConsumerState<QrConfirmPage> {
  bool _submitting = false;

  Future<void> _confirm() async {
    if (_submitting) return;
    // 深链直达可能不带票据：没有票据就没有可确认的对象，直接提示重扫。
    if (widget.qrToken.isEmpty) {
      _toast('二维码信息不完整，请重新扫码');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(authRepositoryProvider).confirmQrLogin(widget.qrToken);
      if (!mounted) return;
      _toast('已确认登录');
      context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('确认失败，请稍后重试');
    }
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(authRepositoryProvider).cancelQrLogin(widget.qrToken);
    } catch (_) {
      // 取消失败不影响用户离开：票据到期自然失效，不把用户卡在确认页。
    }
    if (mounted) context.pop(false);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    return UserCenterScaffold(
      title: '确认登录',
      body: AppPageBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Icon(Icons.laptop_mac_rounded, size: 46, color: AppColors.text2),
              const SizedBox(height: 16),
              const Text(
                '确认登录',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text1),
              ),
              const SizedBox(height: 8),
              const Text(
                '你的账号将登录到下面这台设备上的网页',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.text3),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.public,
                      label: '登录站点',
                      value: target?.portalLabel ?? '创作者端 · 创作者中心',
                    ),
                    const SizedBox(height: 14),
                    _InfoRow(
                      icon: Icons.desktop_windows_outlined,
                      label: '浏览器',
                      value: target?.deviceLabel ?? '未知设备',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warmGray,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: AppColors.warning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '如果这不是你本人正在登录的网页，请点击「取消登录」。切勿为陌生人确认，避免账号被盗用。',
                        style: TextStyle(fontSize: 12.5, height: 1.7, color: AppColors.text2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _submitting ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('确认登录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _submitting ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text2,
                    side: const BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: const Text('取消登录', style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.text3),
        const SizedBox(width: 10),
        SizedBox(
          width: 62,
          child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.text1),
          ),
        ),
      ],
    );
  }
}
