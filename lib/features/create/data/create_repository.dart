import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'create_models.dart';

/// B 模块创作数据层（B 套接口 2.9.1 / 2.9.2 / 2.9.3 / 2.9.7~2.9.9）。
///
/// 只做三件事：拼请求体、解析 App 信封里的 `data`、把 JSON 映射成页面模型。
/// 鉴权与归属由 [ApiClient] 与服务端身份上下文处理，页面绝不上送 userId。
///
/// 「我的作品」写作链路的列表 / 详情 / 章节 / 审核走 A 套
/// [AuthorWorkRepository]（/users/me/works）；本类只保留创建、上传、版本能力。
class CreateRepository {
  CreateRepository(this._api);

  final ApiClient _api;

  /// 文件上传（接口 2.9.1，multipart 字段 `file`；[type] 取 cover/script）。
  Future<UploadResult> uploadFile({
    required String filePath,
    required String fileName,
    String? type,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      if (type != null) 'type': type,
    });
    final data = await _api.upload<Map<String, dynamic>>(
      ApiEndpoints.contentUpload,
      formData: formData,
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('上传失败');
    return UploadResult.fromJson(data);
  }

  /// 封面本地图片上传（接口 2.9.1，multipart 字段 `file`，`type=cover`）。
  ///
  /// 与 [uploadFile] 的差别：入参为内存字节，配合原生选择器使用，
  /// 免去把用户选择的临时文件留在磁盘。返回上传结果的 url。
  Future<String> uploadCoverBytes({
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
      'type': 'cover',
    });
    final data = await _api.upload<Map<String, dynamic>>(
      ApiEndpoints.contentUpload,
      formData: formData,
      parser: _mapParser,
    );
    final url = data?['url'] as String?;
    if (url == null || url.isEmpty) throw ApiException('封面上传失败，请稍后重试');
    return url;
  }

  /// 创建作品（接口 2.9.2）；返回新建的 workId。
  ///
  /// body 字段名对齐契约使用 snake_case（`category_id`），空值字段不下发。
  /// [scriptUrl]/[scriptName]/[scriptSize] 为 2.9.1 上传剧本文件的返回值，
  /// 随创建一并上送，由后端登记到 sys_work_file（作品创建前无从关联）。
  Future<int> createWork({
    required String title,
    required int categoryId,
    String? description,
    String? cover,
    double? price,
    String? scriptUrl,
    String? scriptName,
    int? scriptSize,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentWorks,
      data: _compact({
        'title': title,
        'category_id': categoryId,
        'description': description,
        'cover': cover,
        'price': price,
        'script_url': scriptUrl,
        'script_name': scriptName,
        'script_size': scriptSize,
      }),
      parser: _mapParser,
    );
    final workId = _intOrNull(data?['workId']);
    if (workId == null) throw ApiException('创建作品失败');
    return workId;
  }

  /// 更新作品（接口 2.9.3）；为空的可选字段不更新。非本人/不存在时后端按 404 拒绝。
  ///
  /// 封面与定价的编辑后续批次接入（基本信息走 A 套
  /// [AuthorWorkRepository.updateWorkBase]）。
  Future<void> updateWork(
    int workId, {
    String? title,
    String? description,
    double? price,
  }) async {
    await _api.put<Map<String, dynamic>>(
      ApiEndpoints.contentWorkById(workId),
      data: _compact({'title': title, 'description': description, 'price': price}),
      parser: _mapParser,
    );
  }

  /// 删除作品（接口 2.9.4）；非本人/不存在时后端按 404 拒绝。
  Future<void> deleteWork(int workId) async {
    await _api.delete<Map<String, dynamic>>(
      ApiEndpoints.contentWorkById(workId),
      parser: _mapParser,
    );
  }

  /// 作品版本列表（接口 2.9.7，列表不含 content）。
  Future<List<WorkVersionItem>> listVersions(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkVersions(workId),
      parser: _mapParser,
    );
    return _items(data, WorkVersionItem.fromJson);
  }

  /// 新建作品版本（接口 2.9.8）；[versionDesc] 落 change_log，返回新版本 versionId。
  Future<int> createVersion(
    int workId, {
    String? versionDesc,
    String? content,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentWorkVersions(workId),
      data: _compact({'version_desc': versionDesc, 'content': content}),
      parser: _mapParser,
    );
    final versionId = _intOrNull(data?['versionId']);
    if (versionId == null) throw ApiException('创建版本失败');
    return versionId;
  }

  /// 单版本详情（接口 2.9.9，含 content 全文）。
  Future<WorkVersionDetail> versionDetail(int versionId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkVersionDetail(versionId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取版本详情失败');
    return WorkVersionDetail.fromJson(data);
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  /// 去掉空值字段：后端按「字段缺失 = 不更新/不过滤」处理，传空串会变成无效条件。
  static Map<String, dynamic> _compact(Map<String, dynamic> raw) {
    final body = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      body[key] = value;
    });
    return body;
  }

  static List<T> _items<T>(
    Map<String, dynamic>? data,
    T Function(Map<String, dynamic> item) parser,
  ) {
    final raw = data?['list'];
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map>()
        .map((e) => parser(Map<String, dynamic>.from(e)))
        .toList();
  }

  static int? _intOrNull(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) return int.tryParse(value);
    return null;
  }
}