import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'user_center_models.dart';

/// A5 用户中心数据访问（契约 A5-USER-CENTER-CONTRACT-v1）。
///
/// 页面只调用本仓库，不直接接触 Dio / Token / Storage。
class UserCenterRepository {
  UserCenterRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------
  // 个人资料（§1.2）
  // ------------------------------------------------------------------

  Future<UserProfile> profile() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.myProfile,
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取个人资料失败');
    return UserProfile.fromJson(data);
  }

  /// 只提交需要修改的字段；两个字段都不传时后端返回 400，此处提前拦截。
  Future<UserProfile> updateProfile({String? nickname, String? avatar}) async {
    if (nickname == null && avatar == null) {
      throw ApiException('没有需要保存的修改');
    }
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.myProfile,
      data: {
        if (nickname != null) 'nickname': nickname,
        if (avatar != null) 'avatar': avatar,
      },
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('保存失败，请稍后重试');
    return UserProfile.fromJson(data);
  }

  /// 上传头像，返回可直接展示与保存的地址。
  ///
  /// 走 App 凭证域专用端点 `POST /api/v1/users/me/avatar`：
  /// 平台原生的 `/common/upload` 属于 PC 凭证链，App Token 在其上无法通过鉴权，
  /// 且其响应为若依 AjaxResult（url 在顶层），与 App 的 `{code,message,data}` 信封不一致。
  /// 本端点复用同一上传目录与校验规则，响应为 App 信封，因此走统一的 [ApiClient.upload]。
  Future<String> uploadAvatar({
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: contentType == null ? null : DioMediaType.parse(contentType),
      ),
    });
    try {
      final data = await _api.upload<Map<String, dynamic>>(
        ApiEndpoints.myAvatar,
        formData: formData,
        parser: _mapParser,
      );
      final url = data?['url'] as String?;
      if (url == null || url.isEmpty) {
        throw ApiException('头像上传失败，请稍后重试');
      }
      return url;
    } on DioException catch (e) {
      throw ApiException(_uploadErrorMessage(e));
    }
  }

  String _uploadErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '上传超时，请稍后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络后重试';
      default:
        return '头像上传失败，请稍后重试';
    }
  }

  // ------------------------------------------------------------------
  // 实名认证（§1.3）
  // ------------------------------------------------------------------

  Future<RealNameStatus> realNameStatus() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.myRealName,
      parser: _mapParser,
    );
    return RealNameStatus.fromJson(data ?? const {});
  }

  /// 首次提交与驳回后重提走两个契约端点；由调用方根据当前状态选择。
  Future<RealNameStatus> submitRealName({
    required String realName,
    required String idNumber,
    required List<String> materialRefs,
    required bool resubmit,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      resubmit ? ApiEndpoints.myRealNameResubmit : ApiEndpoints.myRealName,
      data: {
        'realName': realName,
        'idNumber': idNumber,
        'materialRefs': materialRefs,
      },
      parser: _mapParser,
    );
    return RealNameStatus.fromJson(data ?? const {});
  }

  // ------------------------------------------------------------------
  // 账号安全：换绑手机号（§1.4）
  // ------------------------------------------------------------------

  /// 第 1 步（a）：向当前登录用户自己的手机号发送换绑验证码。
  ///
  /// 走用户中心专用端点而不是公开的 `/auth/sms/send`：号码由服务端按当前身份取，
  /// 客户端不需要、也无法指定发往哪个号码（页面只持有脱敏号）。
  Future<String?> sendOldPhoneCode() async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.phoneChangeOldSend,
      data: {'deviceId': _deviceId},
      parser: _mapParser,
    );
    return data?['phoneMasked'] as String?;
  }

  /// 第 1 步：验证旧号，取回一次性 step-up 凭证。
  Future<PhoneStepUp> verifyOldPhone(String code) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.phoneChangeOldVerify,
      data: {'code': code, 'deviceId': _deviceId},
      parser: _mapParser,
    );
    final stepUp = PhoneStepUp.fromJson(data ?? const {});
    if (stepUp.stepUpToken.isEmpty) {
      throw ApiException('旧手机号验证失败，请重试');
    }
    return stepUp;
  }

  /// 第 2 步：向新号发码（服务端会先校验新号未被占用）。
  Future<void> sendNewPhoneCode(String newPhone) async {
    await _api.post(
      ApiEndpoints.phoneChangeNewSend,
      data: {'newPhone': newPhone, 'deviceId': _deviceId},
    );
  }

  /// 第 3 步：确认换绑。成功后后端吊销全部会话，客户端须重新登录。
  Future<String?> confirmPhoneChange({
    required String newPhone,
    required String code,
    required String stepUpToken,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.phoneChangeConfirm,
      data: {
        'newPhone': newPhone,
        'code': code,
        'stepUpToken': stepUpToken,
        'deviceId': _deviceId,
      },
      parser: _mapParser,
    );
    return data?['phoneMasked'] as String?;
  }

  /// 与 A3 一致的设备标识来源：当前客户端未接入设备指纹，使用固定值。
  static const String _deviceId = 'flutter-device';

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}
