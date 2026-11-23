import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/update/data/apk_installer.dart';
import 'package:script_app/features/update/data/app_update_providers.dart';
import 'package:script_app/features/update/data/app_update_repository.dart';
import 'package:script_app/features/update/data/app_version_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只替换网络层：检查器对「要不要弹」的判断（每日限制、运行内去重）才是被测对象。
class _FakeRepository extends AppUpdateRepository {
  _FakeRepository(this.info) : super(ApiClient(Dio()));

  final AppVersionInfo info;
  int fetches = 0;

  @override
  Future<AppVersionInfo> fetchLatest() async {
    fetches++;
    return info;
  }
}

const _normalUpdate = AppVersionInfo(
  versionCode: 3,
  versionName: '1.0.2',
  minVersionCode: 0,
  url: '/profile/app/script-app-1.0.2-3.apk',
  notes: '修复若干问题',
);

const _forcedUpdate = AppVersionInfo(
  versionCode: 3,
  versionName: '1.0.2',
  minVersionCode: 2,
  url: '/profile/app/script-app-1.0.2-3.apk',
  notes: '必要更新',
);

String _dayText(DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  return '${day.year}-$month-${day.day.toString().padLeft(2, '0')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // 本机 build 低于更新包 versionCode，保证每次检查都能拿到「有更新」。
    ApkInstaller.debugLocalBuildNumber = 1;
  });

  tearDown(() {
    ApkInstaller.debugLocalBuildNumber = null;
  });

  Future<AppUpdateChecker> checker(AppVersionInfo info) async =>
      AppUpdateChecker(_FakeRepository(info), prefs);

  test('冷启动弹过一次后，当天切回前台不再弹（下拉通知栏/回桌面再回来）', () async {
    final update = await checker(_normalUpdate);

    expect(await update.checkForLaunch(), isNotNull);
    await update.markPromptShown();

    expect(await update.checkOnResume(), isNull);
    expect(await update.checkOnResume(), isNull);
  });

  test('当天已记录弹窗日期时，重新启动进程也不再弹', () async {
    await prefs.setString(
        AppUpdateChecker.promptDayKey, _dayText(DateTime.now()));

    final relaunched = await checker(_normalUpdate);
    expect(await relaunched.checkForLaunch(), isNull);
  });

  test('记录的是昨天时，第二天照常弹一次', () async {
    await prefs.setString(AppUpdateChecker.promptDayKey,
        _dayText(DateTime.now().subtract(const Duration(days: 1))));

    final tomorrow = await checker(_normalUpdate);
    expect(await tomorrow.checkForLaunch(), isNotNull);
  });

  test('同一次运行内冷启动与切回前台只提示一次', () async {
    final update = await checker(_normalUpdate);
    expect(await update.checkForLaunch(), isNotNull);
    // 即使没有 markPromptShown（弹窗还没点按钮），运行内也不再重复弹。
    expect(await update.checkOnResume(), isNull);
  });

  test('强制更新不受每日限制，切回前台仍会提醒', () async {
    await prefs.setString(
        AppUpdateChecker.promptDayKey, _dayText(DateTime.now()));

    final update = await checker(_forcedUpdate);
    final prompt = await update.checkForLaunch();
    expect(prompt?.forced, isTrue);
    await update.markPromptShown();
    expect(await update.checkOnResume(), isNotNull);
  });

  test('手动「检查更新」不受每日限制', () async {
    await prefs.setString(
        AppUpdateChecker.promptDayKey, _dayText(DateTime.now()));

    final update = await checker(_normalUpdate);
    expect(await update.checkManually(), isNotNull);
  });

  test('已是最新版本时不会写入弹窗记录', () async {
    final repository = _FakeRepository(const AppVersionInfo(
      versionCode: 1,
      versionName: '1.0.0',
      minVersionCode: 0,
      url: '/profile/app/old.apk',
      notes: '',
    ));
    final update = AppUpdateChecker(repository, prefs);

    expect(await update.checkForLaunch(), isNull);
    expect(prefs.getString(AppUpdateChecker.promptDayKey), isNull);
  });
}
