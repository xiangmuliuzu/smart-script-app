import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/auth_feedback.dart';
import '../../auth/widgets/verify_code_input.dart';
import '../data/create_providers.dart';

/// 删除作品前验证绑定手机号；仅成功删除返回 true，取消或失败均保留作品。
class WorkDeleteDialog extends ConsumerStatefulWidget {
  const WorkDeleteDialog({
    super.key,
    required this.workId,
    required this.title,
  });

  final int workId;
  final String title;

  @override
  ConsumerState<WorkDeleteDialog> createState() => _WorkDeleteDialogState();
}

class _WorkDeleteDialogState extends ConsumerState<WorkDeleteDialog> {
  final _codeController = TextEditingController();
  String? _phoneMasked;
  String? _error;
  int _cooldownSeconds = AppConfig.smsCooldownSeconds;
  bool _sending = false;
  bool _deleting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<bool> _sendCode() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(createRepositoryProvider)
          .sendDeletionCode(widget.workId);
      if (!mounted) return false;
      setState(() {
        _phoneMasked = data['phoneMasked'] as String?;
        _cooldownSeconds = (data['cooldownSeconds'] as num?)?.toInt() ??
            AppConfig.smsCooldownSeconds;
      });
      // 先让输入组件收到服务端重发间隔，再通知它启动倒计时。
      await WidgetsBinding.instance.endOfFrame;
      return mounted;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = AuthFeedback.smsSendError(e));
    } catch (_) {
      if (mounted) setState(() => _error = '验证码发送失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    return false;
  }

  Future<void> _delete() async {
    if (_deleting || _sending) return;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(code)) {
      setState(() => _error = '请输入正确格式的验证码');
      return;
    }
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref
          .read(createRepositoryProvider)
          .deleteWork(widget.workId, code: code);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = AuthFeedback.apiMessage(e));
    } catch (_) {
      if (mounted) setState(() => _error = '删除失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sending || _deleting;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('删除作品'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定删除《${widget.title}》吗？'),
              const SizedBox(height: 12),
              const Text(
                  '删除后作品将下架，并从我的作品中移除，无法自行恢复。有关联订单、合同或付费记录的作品不能删除，请使用下架功能。'),
              const SizedBox(height: 12),
              Text(_phoneMasked == null
                  ? '请获取绑定手机号或邮箱的验证码，验证身份后删除。'
                  : '验证码已发送至 $_phoneMasked'),
              const SizedBox(height: 8),
              VerifyCodeInput(
                controller: _codeController,
                onRequestCode: _sendCode,
                cooldownSeconds: _cooldownSeconds,
                enabled: !busy,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(_deleting ? '删除中…' : '验证并删除'),
          ),
        ],
      ),
    );
  }
}
