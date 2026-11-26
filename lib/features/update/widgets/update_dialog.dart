import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/friendly_error.dart';
import '../../../core/theme/app_colors.dart';
import '../data/apk_installer.dart';
import '../data/app_update_providers.dart';
import '../data/app_update_repository.dart';
import '../data/app_version_models.dart';

/// 弹出更新提示。返回用户是否点了「稍后」（强制更新时恒为 false）。
Future<bool> showUpdateDialog({
  required BuildContext context,
  required AppUpdatePrompt prompt,
  required AppUpdateRepository repository,
}) async {
  final skipped = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => UpdateDialog(prompt: prompt, repository: repository),
  );
  return skipped ?? false;
}

/// 应用内更新弹窗：显示版本说明、在应用内下载（不跳浏览器）、下载完拉起系统安装器。
///
/// 普通应用无法静默安装，安装确认框由系统弹出，这是平台限制。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.prompt,
    required this.repository,
  });

  final AppUpdatePrompt prompt;
  final AppUpdateRepository repository;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, downloading, awaitingInstall }

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String? _error;
  String? _downloadedPath;
  CancelToken? _cancelToken;

  AppVersionInfo get _info => widget.prompt.info;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (_phase == _Phase.downloading) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = null;
    });
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final dir = await ApkInstaller.downloadDirectory();
      // 先清掉更早版本留下的安装包，避免应用目录越攒越大。
      await ApkInstaller.cleanupOldApks(dir);
      final file = File(
          '${dir.path}/script-app-${_info.versionName}-${_info.versionCode}.apk');
      // 旧包残留会导致无法覆盖安装，先清理同名文件。
      if (await file.exists()) await file.delete();
      await widget.repository.download(
        url: _info.url,
        savePath: file.path,
        cancelToken: cancelToken,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      final expected = _info.size;
      if (expected != null && expected > 0) {
        final actual = await file.length();
        if (actual != expected) {
          await file.delete();
          throw const ApkDownloadException('安装包不完整，请重新下载');
        }
      }
      if (!await ApkInstaller.looksLikeApk(file)) {
        // 常见于服务器/网关把 404 或维护页当成功返回，或对象存储里放错了文件。
        await file.delete();
        throw const ApkDownloadException('安装包异常，请稍后重试');
      }
      _downloadedPath = file.path;
      setState(() => _phase = _Phase.awaitingInstall);
      await _install();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _error = FriendlyError.network;
        });
      }
    } on ApkDownloadException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = e.message;
      });
    } catch (_) {
      // 下载/落盘的其他异常（磁盘空间等）统一兜底
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = '下载失败，请稍后重试';
      });
    }
  }

  Future<void> _install() async {
    final path = _downloadedPath;
    if (path == null) {
      await _startDownload();
      return;
    }
    try {
      final started = await ApkInstaller.install(path);
      if (!mounted) return;
      if (started) {
        // 系统安装器已覆盖在当前页面之上；关闭弹窗，用户取消安装时回到 App。
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _phase = _Phase.awaitingInstall;
        _error = '请允许本应用「安装未知应用」，返回后点「立即安装」';
      });
    } on ApkInstallException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.awaitingInstall;
        _error = e.message;
      });
    }
  }

  void _skip() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _phase == _Phase.downloading;
    final notes = _info.notes.trim();
    return Dialog(
        key: const Key('app-update-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 32,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryTint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update_alt,
                          size: 22, color: AppColors.text1),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '发现新版本 ${_info.versionName}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.prompt.forced ? '本次更新为必要更新' : '更新以获得更好的使用体验',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.32,
                    ),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.fill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        notes,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.6,
                          color: AppColors.text2,
                        ),
                      ),
                    ),
                  ),
                ],
                if (downloading) ...[
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 6,
                      backgroundColor: AppColors.divider,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _progress > 0
                        ? '正在下载 ${(_progress * 100).toStringAsFixed(0)}%'
                        : '正在准备下载…',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.text3),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.danger, height: 1.5),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (!widget.prompt.forced) ...[
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('app-update-skip'),
                          onPressed: downloading ? null : _skip,
                          child: const Text('稍后'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(
                        key: const Key('app-update-action'),
                        onPressed: downloading ? null : _primaryAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(_actionLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }

  String get _actionLabel {
    if (_phase == _Phase.downloading) return '下载中…';
    if (_phase == _Phase.awaitingInstall) return '立即安装';
    return '立即更新';
  }

  void _primaryAction() {
    if (_phase == _Phase.awaitingInstall) {
      _install();
      return;
    }
    _startDownload();
  }
}
