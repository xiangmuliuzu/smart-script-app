// E 模块：福利任务行为埋点（真实行为 → 上报进度）。
//
// 覆盖：
//   - 找到对应 taskType 的未领取任务并调用 /welfare/task/progress；
//   - 任务列表中不存在该类型时静默跳过（不报错）；
//   - 上报接口失败时静默（不抛异常，不影响主流程）。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/welfare/data/welfare_providers.dart';
import 'package:script_app/models/user.dart';

import '../support/scripted_api.dart';

class _FakeSecureStorage implements TokenSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

/// 只实现 me()：让 AuthController 的启动恢复直接得到指定身份。
class _MeRepo implements AuthRepository {
  _MeRepo(this.user);

  final User user;

  @override
  Future<User> me() async => user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _testUser = User(userId: 106, userType: UserType.user, nickname: '测试用户');

void main() {
  late ScriptedApi api;

  setUp(() {
    api = ScriptedApi();
  });

  Future<ProviderContainer> buildContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = _FakeSecureStorage();
    await secure.write(AppConstants.kAccessToken, 'token-for-test');
    final storage = TokenStorage(secure, prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider.overrideWithValue(secure),
        tokenStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(_MeRepo(_testUser)),
        api.override,
      ],
    );
    addTearDown(container.dispose);
    // 启动恢复是构造时异步触发的：轮询等待会话恢复得到已登录身份
    for (var i = 0;
        i < 50 && container.read(authControllerProvider).user == null;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(authControllerProvider).user?.userId, 106,
        reason: '测试前置：会话恢复必须得到已登录身份');
    return container;
  }

  test('找到对应类型未领取任务并上报进度', () async {
    api.reply('/welfare/tasks', Envelope.ok({
      'tasks': [
        {
          'taskId': 1,
          'taskName': '阅读任务',
          'taskType': 'READING',
          'taskCode': 'READ_CHAPTER',
          'description': '',
          'targetCount': 3,
          'rewardPoints': 10,
          'icon': '',
          'progress': 0,
          'isCompleted': 0,
          'isClaimed': 0,
          'periodDate': null,
        },
      ],
    }));
    api.reply('/welfare/task/progress', Envelope.ok({
      'progress': 1,
      'targetCount': 3,
      'isCompleted': 0,
    }));

    final container = await buildContainer();
    await reportTaskProgressByType(container, 'READING');

    final progressReqs =
        api.requests.where((r) => r.path.contains('/welfare/task/progress')).toList();
    expect(progressReqs.length, 1, reason: '应上报一次阅读任务进度');
    expect(progressReqs.first.data['taskCode'], 'READ_CHAPTER');
    expect(progressReqs.first.data['userId'], 106);
    expect(progressReqs.first.data['increment'], 1);
  });

  test('任务列表无该类型时静默跳过，不发请求', () async {
    api.reply('/welfare/tasks', Envelope.ok({
      'tasks': [
        {
          'taskId': 1,
          'taskName': '每日任务',
          'taskType': 'DAILY',
          'taskCode': 'DAILY_LOGIN',
          'description': '',
          'targetCount': 1,
          'rewardPoints': 5,
          'icon': '',
          'progress': 0,
          'isCompleted': 0,
          'isClaimed': 0,
          'periodDate': null,
        },
      ],
    }));

    final container = await buildContainer();
    await reportTaskProgressByType(container, 'READING');

    expect(api.countOf('/welfare/task/progress'), 0,
        reason: '没有 READING 任务不应上报');
  });

  test('上报接口失败时静默，不抛异常', () async {
    api.reply('/welfare/tasks', Envelope.ok({
      'tasks': [
        {
          'taskId': 2,
          'taskName': '上传任务',
          'taskType': 'UPLOAD',
          'taskCode': 'UPLOAD_WORK',
          'description': '',
          'targetCount': 1,
          'rewardPoints': 20,
          'icon': '',
          'progress': 0,
          'isCompleted': 0,
          'isClaimed': 0,
          'periodDate': null,
        },
      ],
    }));
    // 不注册 progress 路由 → ScriptedApi 返回 500「no scripted route」，
    // ApiClient 将其转为 ApiException；helper 必须静默吞掉。

    final container = await buildContainer();
    await reportTaskProgressByType(container, 'UPLOAD');
    // 到达此处即未抛异常
  });
}
