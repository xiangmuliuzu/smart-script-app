import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'create_models.dart';

/// B 模块「上传与创作」数据层（接口 2.9.1 / 2.9.2~2.9.9）。
///
/// 只做三件事：拼请求体、解析 App 信封里的 `data`、把 JSON 映射成页面模型。
/// 鉴权与归属由 [ApiClient] 与服务端身份上下文处理，页面绝不上送 userId。
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

  /// 创建作品（接口 2.9.2）；返回新建的 workId。
  ///
  /// body 字段名对齐契约使用 snake_case（`category_id`），空值字段不下发。
  Future<int> createWork({
    required String title,
    required int categoryId,
    String? description,
    String? cover,
    double? price,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentWorks,
      data: _compact({
        'title': title,
        'category_id': categoryId,
        'description': description,
        'cover': cover,
        'price': price,
      }),
      parser: _mapParser,
    );
    final workId = _intOrNull(data?['workId']);
    if (workId == null) throw ApiException('创建作品失败');
    return workId;
  }

  /// 更新作品（接口 2.9.3）；为空的可选字段不更新。非本人/不存在时后端按 404 拒绝。
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

  /// 我的草稿箱（接口 2.9.5，分页 {total, list}）。
  Future<PagedData<DraftWorkItem>> pageDrafts({
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentDrafts,
      query: {'page': pageNum, 'pageSize': pageSize},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取草稿列表失败');
    return PagedData.parse<DraftWorkItem>(data, DraftWorkItem.fromJson);
  }

  /// 作品审核状态（接口 2.9.6）。
  Future<ReviewStatus> reviewStatus(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentReviewStatus(workId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取审核状态失败');
    return ReviewStatus.fromJson(data);
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

  /// 作者视角章节列表（章节管理用；接口文档无 CRUD 规格，按模块约定补齐）。
  ///
  /// 走 /works/{workId}/chapters/manage：不过滤 status，隐藏章节也在列，便于恢复。
  /// 不能用书城目录接口：它对作品强制 status='on_shelf'，草稿作品会 404。
  Future<List<AuthorChapterItem>> listWorkChapters(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkChaptersManage(workId),
      parser: _mapParser,
    );
    return _items(data, AuthorChapterItem.fromJson);
  }

  /// 新增章节（接口文档无规格，按模块约定补齐）；返回新建的 chapterId。
  ///
  /// 后端按 body 的 camelCase 字段名接收；空值字段不下发（isFree 缺省由后端补 "0"）。
  Future<int> createChapter(
    int workId, {
    required int chapterNo,
    required String chapterTitle,
    String? content,
    String? isFree,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentWorkChapters(workId),
      data: _compact({
        'chapterNo': chapterNo,
        'chapterTitle': chapterTitle,
        'content': content,
        'isFree': isFree,
      }),
      parser: _mapParser,
    );
    final chapterId = _intOrNull(data?['chapterId']);
    if (chapterId == null) throw ApiException('新增章节失败');
    return chapterId;
  }

  /// 更新章节（接口文档无规格，按模块约定补齐）；为空的字段不更新。
  ///
  /// 非本人作品/章节不存在时后端按 403/404 拒绝；wordCount 由后端按正文重算。
  Future<void> updateChapter(
    int chapterId, {
    String? chapterTitle,
    String? content,
    String? isFree,
    String? status,
  }) async {
    await _api.put<Map<String, dynamic>>(
      ApiEndpoints.contentChapter(chapterId),
      data: _compact({
        'chapterTitle': chapterTitle,
        'content': content,
        'isFree': isFree,
        'status': status,
      }),
      parser: _mapParser,
    );
  }

  /// 删除章节（接口文档无规格，按模块约定补齐，物理删除）。
  Future<void> deleteChapter(int chapterId) async {
    await _api.delete<Map<String, dynamic>>(
      ApiEndpoints.contentChapter(chapterId),
      parser: _mapParser,
    );
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