import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'apk_installer.dart';
import 'app_update_repository.dart';
import 'app_version_models.dart';

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>(
  (ref) => AppUpdateRepository(ref.watch(apiClientProvider)),
);

/// 需要提示的更新：版本信息 + 是否强制。
class AppUpdatePrompt {
  const AppUpdatePrompt({required this.info, required this.forced});

  final AppVersionInfo info;

  /// 用户点「稍后」也不应关闭（本机 build 低于后台设置的强制下限）。
  final bool forced;
}

/// 版本检查入口（冷启动 / 切回前台 / 我的 → 检查更新 共用）。
///
/// 只负责「要不要弹」：后台未配置、本机已是最新、检查失败都返回 null，
/// 不阻塞 App 使用。
class AppUpdateChecker {
  AppUpdateChecker(this._repository);

  final AppUpdateRepository _repository;

  bool _checking = false;

  /// 本次运行是否已做过冷启动检查（冷启动只弹一次，切回前台不重复打扰）。
  bool _launchChecked = false;

  /// 冷启动检查：每次运行最多一次。
  Future<AppUpdatePrompt?> checkForLaunch() async {
    if (_launchChecked) return null;
    _launchChecked = true;
    return _check();
  }

  /// 手动检查（「检查更新」入口，用户主动触发）。
  Future<AppUpdatePrompt?> checkManually() => _check();

  Future<AppUpdatePrompt?> _check() async {
    if (_checking) return null;
    _checking = true;
    try {
      final info = await _repository.fetchLatest();
      final local = await ApkInstaller.localBuildNumber();
      if (!info.isNewerThan(local)) return null;
      return AppUpdatePrompt(info: info, forced: info.isForcedFor(local));
    } finally {
      _checking = false;
    }
  }
}

final appUpdateCheckerProvider = Provider<AppUpdateChecker>(
  (ref) => AppUpdateChecker(ref.watch(appUpdateRepositoryProvider)),
);
