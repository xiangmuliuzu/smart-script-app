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

  /// 只提交需要修改的字段；三个字段都不传时后端返回 400，此处提前拦截。
  /// [bio] 传空串表示清空简介（后端契约允许），传 null 表示不修改；
  /// 超过 200 字符（后端上限）在本地直接拒绝，不发请求。
  Future<UserProfile> updateProfile(
      {String? nickname, String? avatar, String? bio}) async {
    if (nickname == null && avatar == null && bio == null) {
      throw ApiException('没有需要保存的修改');
    }
    if (bio != null && bio.length > 200) {
      throw ApiException('简介不能超过 200 个字符');
    }
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.myProfile,
      data: {
        if (nickname != null) 'nickname': nickname,
        if (avatar != null) 'avatar': avatar,
        if (bio != null) 'bio': bio,
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
        contentType:
            contentType == null ? null : DioMediaType.parse(contentType),
      ),
    });
    try {
      final data = await _api.upload<Map<String, dynamic>>(
        ApiEndpoints.myAvatar,
        formData: formData,
        parser: _mapParser,
      );
      // 保存站内路径，展示时由客户端按当前后端地址解析；旧后端兼容 url。
      final url = (data?['path'] as String?) ?? (data?['url'] as String?);
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

  /// 上传审核专用材料；返回内部引用，不提供公开图片地址。
  Future<String> uploadRealNameMaterial({
    required List<int> bytes,
    required String filename,
  }) async {
    final data = await _api.upload<Map<String, dynamic>>(
      ApiEndpoints.myRealNameMaterial,
      formData: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      parser: _mapParser,
    );
    final reference = data?['materialRef'];
    if (reference is! String || reference.trim().isEmpty) {
      throw ApiException('材料上传失败，请稍后重试');
    }
    return reference;
  }

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
    List<String> materialRefs = const [],
    required bool resubmit,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      resubmit ? ApiEndpoints.myRealNameResubmit : ApiEndpoints.myRealName,
      data: {
        'realName': realName,
        'idNumber': idNumber,
        if (materialRefs.isNotEmpty) 'materialRefs': materialRefs,
      },
      parser: _mapParser,
    );
    return RealNameStatus.fromJson(data ?? const {});
  }

  // ------------------------------------------------------------------
  // 创作者申请（§1.6）
  // ------------------------------------------------------------------

  Future<CreatorApplyStatus> creatorApplyStatus() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.myCreatorApply,
      parser: _mapParser,
    );
    return CreatorApplyStatus.fromJson(data ?? const {});
  }

  /// 提交创作者申请。驳回后重提复用同一端点（服务端按状态机准入，无需区分路径）。
  Future<CreatorApplyStatus> submitCreatorApply({
    required String penName,
    required String direction,
    String? portfolio,
    required String intro,
    required String contact,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.myCreatorApply,
      data: {
        'penName': penName,
        'direction': direction,
        if (portfolio != null && portfolio.isNotEmpty) 'portfolio': portfolio,
        'intro': intro,
        'contact': contact,
      },
      parser: _mapParser,
    );
    return CreatorApplyStatus.fromJson(data ?? const {});
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
