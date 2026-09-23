import '../../../core/config/app_config.dart';
import 'auth_repository.dart';

/// 协议类型的服务端标识（与后端 `AgreementService` 常量一致）。
class AgreementTypes {
  AgreementTypes._();

  static const String userAgreement = 'USER_AGREEMENT';
  static const String privacyPolicy = 'PRIVACY_POLICY';
}

/// 从既有 `GET /auth/agreements` 读取指定协议的最新版本号。
///
/// 版本号只用于展示（与提交时的 `agreementAcceptances` 同源）；
/// 网络异常或字段缺失时回退到 [AppConfig.agreementVersion]，
/// 保证登录前的协议正文始终可读。
Future<String> fetchAgreementVersion(
  AuthRepository repository, {
  required String type,
  String fallback = AppConfig.agreementVersion,
}) async {
  try {
    final list = await repository.agreements();
    for (final item in list) {
      if (item['type'] != type) {
        continue;
      }
      final version = item['version'];
      if (version is String && version.isNotEmpty) {
        return version;
      }
    }
  } catch (_) {
    // 忽略：使用兜底版本展示，不阻断阅读
  }
  return fallback;
}
