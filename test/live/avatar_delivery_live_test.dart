import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/utils/avatar_url.dart';
import 'package:script_app/features/user_center/data/user_center_repository.dart';

/// 本地头像联调使用临时账号，会话文件由验证脚本生成并清理。
void main() {
  final sessionPath = Platform.environment['AVATAR_SESSION_FILE'] ?? '';
  test('App真实仓库上传保存站内路径，PC与App会话获取同一头像', () async {
    final session = jsonDecode(await File(sessionPath).readAsString()) as Map;
    expect(session['baseUrl'], 'http://127.0.0.1:8080/api/v1');
    ApiClient client(String token) => ApiClient(Dio(BaseOptions(
          baseUrl: session['baseUrl'] as String,
          headers: {'Authorization': 'Bearer $token'},
        )));
    final app = client(session['appToken'] as String);
    final pc = UserCenterRepository(client(session['pcToken'] as String));
    final repository = UserCenterRepository(app);
    expect((await repository.profile()).avatar, session['pcAvatar']);
    final bytes = await File(session['imageFile'] as String).readAsBytes();
    final uploaded =
        await repository.uploadAvatar(bytes: bytes, filename: 'avatar.png');
    await File(session['outputFile'] as String)
        .writeAsString(jsonEncode({'path': uploaded}));
    expect(uploaded, startsWith('/profile/upload/'));
    final saved = await repository.updateProfile(avatar: uploaded);
    expect(saved.avatar, uploaded);
    expect((await pc.profile()).avatar, uploaded);
    final me = await app.get<Map<String, dynamic>>('/auth/me',
        parser: (raw) => Map<String, dynamic>.from(raw as Map));
    expect(me?['avatar'], uploaded);
    final response = await Dio().get<List<int>>(
      avatarUrl(uploaded, baseUrl: session['baseUrl'] as String),
      options: Options(responseType: ResponseType.bytes),
    );
    expect(response.statusCode, 200);
    expect(response.data, bytes);
  }, skip: sessionPath.isEmpty ? '仅在提供本地头像夹具会话时运行' : false);
}
