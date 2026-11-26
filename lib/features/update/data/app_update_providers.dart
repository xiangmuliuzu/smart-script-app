import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_time.dart';
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
///
/// 自动检查（冷启动、切回前台）一天最多弹一次：下拉通知栏、回桌面再回来都会触发
/// `resumed`，若不记录就会每次切前台都重新弹同一个更新。已弹过的日期写在
/// SharedPreferences（非敏感缓存），跨进程保留，第二天自动失效；强制更新不受此限制。
class AppUpdateChecker {
  AppUpdateChecker(this._repository, this._prefs);

  final AppUpdateRepository _repository;
  final SharedPreferences _prefs;

  /// 最近一次自动弹窗的本地日期（yyyy-MM-dd）。
  static const String promptDayKey = 'app_update_prompt_day';

  bool _checking = false;

  /// 本次运行是否已做过冷启动检查（冷启动只弹一次，切回前台不重复打扰）。
  bool _launchChecked = false;

  /// 本次运行是否已经自动弹过更新提示（不论用户是否点了「稍后」）。
  bool _promptedThisRun = false;

  /// 冷启动检查：每次运行最多一次，且当天自动弹过则不再重复。
  Future<AppUpdatePrompt?> checkForLaunch() async {
    if (_launchChecked) return null;
    _launchChecked = true;
    return _automaticPrompt();
  }

  /// 切回前台检查：与冷启动共用「一天一次」的限制。
  Future<AppUpdatePrompt?> checkOnResume() => _automaticPrompt();

  /// 手动检查（「检查更新」入口，用户主动触发）：不受每日限制。
  Future<AppUpdatePrompt?> checkManually() => _check();

  /// 记下「今天已经自动弹过更新」，供下次冷启动 / 切回前台时跳过。
  Future<void> markPromptShown() async {
    await _prefs.setString(promptDayKey, _today());
  }

  Future<AppUpdatePrompt?> _automaticPrompt() async {
    if (_promptedThisRun) return null;
    final prompt = await _check();
    if (prompt == null) return null;
    if (!prompt.forced) {
      // 普通更新：当天已自动弹过就不再打扰。
      if (_prefs.getString(promptDayKey) == _today()) return null;
      _promptedThisRun = true;
    }
    return prompt;
  }

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

  /// 当天日期按北京自然日取：设备时区不可信（见 [AppTime]），跨时区或改系统时间
  /// 都不应让「一天一次」提前失效或重复触发。
  static String _today() => AppTime.formatDate(AppTime.nowBeijing());
}

final appUpdateCheckerProvider = Provider<AppUpdateChecker>(
  (ref) => AppUpdateChecker(
    ref.watch(appUpdateRepositoryProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);
