import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'author_work_models.dart';

/// B 模块「我的作品」写作链路数据层。
///
/// 只做三件事：拼请求、解析 App 信封里的 `data`、把 JSON 映射成页面模型。
/// 归属与鉴权由服务端身份上下文处理，页面绝不上送 userId。
///
/// 接口分工：
///   - 作品列表 / 详情 / 基本信息 / 提交审核 / 审核记录走 A 套 `/users/me/works/**`；
///   - 章节增删改走 B 套 `/content/**`（A 套章节写死 isFree="0" 且不接收 status，
///     无法实现「试读章节」，故写入统一切到支持 isFree/status 的 B 套）；
///   - 章节列表读取仍随 A 套作品详情一次下发（含正文，供编辑器回填）。
class AuthorWorkRepository {
  AuthorWorkRepository(this._api);

  final ApiClient _api;

  /// 我的作品列表（A 套 GET /users/me/works）。
  ///
  /// [status] 取 all/draft/reviewing/revision/rejected/published；
  /// 传 null 或 all 时后端返回全部。列表不分页。
  Future<List<AuthorWorkItem>> listWorks({String? status}) async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.authorWorks,
      query: (status == null || status == 'all') ? null : {'status': status},
      parser: _listParser,
    );
    return _mapItems(data, AuthorWorkItem.fromJson);
  }

  /// 作品详情（含章节目录与最近审核意见；A 套一次拿全）。
  Future<AuthorWorkDetail> workDetail(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.authorWorkById(workId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取作品详情失败');
    return AuthorWorkDetail.fromJson(data);
  }

  /// 修改作品基本信息（标题 / 简介 / 分类 / 封面 / 标签）。
  ///
  /// 空值字段不下发（后端按「字段缺失 = 不更新」处理）；仅审核中锁定，
  /// 其余状态（含已发布）可改，否则后端按 400 拒绝并在 message 中说明当前状态。
  ///
  /// [tagIds] 按接口文档 2.3.3 为**全量覆盖**语义，最多 8 个：
  /// 传 null 表示不改标签，传空列表表示清空标签（因此不能被 [_compact] 过滤掉）。
  ///
  /// [summary] 为唯一豁免空串过滤的字段：后端 SQL 为 `summary != null 即更新`，
  /// 空串用于把简介**清空**；传 null 才表示不更新简介。
  Future<void> updateWorkBase(
    int workId, {
    String? title,
    String? summary,
    int? genreId,
    String? cover,
    List<int>? tagIds,
  }) async {
    final body = _compact({
      'title': title,
      'summary': summary,
      'genreId': genreId,
      'cover': cover,
      'tagIds': tagIds,
    });
    // 重新写回 summary：_compact 会丢弃空串，但后端支持把 summary 置空，
    // 故只要调用方显式传了 summary（含空串）就必须下发；其它字段语义不变。
    if (summary != null) body['summary'] = summary;
    await _api.put<Map<String, dynamic>>(
      ApiEndpoints.authorWorkById(workId),
      data: body,
      parser: _mapParser,
    );
  }

  /// 提交审核（draft/revision/rejected/published → reviewing）。
  ///
  /// 已发布作品改动后重新提交也走此接口；审核中重复提交由后端按 400 拒绝。
  Future<void> submitReview(int workId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.authorWorkSubmit(workId),
      parser: _mapParser,
    );
  }

  /// 新增章节（B 套 POST /content/works/{workId}/chapters）。
  ///
  /// [chapterNo] 为作品内唯一正整数，由调用方按当前最大序号 +1 计算；
  /// [isFree] 为 true 时标记为免费试读章节（后端落 is_free="1"）。
  /// 返回新建章节的 chapterId；序号重复或标题非法时后端按 400 拒绝。
  Future<int> addChapter(
    int workId, {
    required int chapterNo,
    required String chapterTitle,
    String? content,
    bool isFree = false,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentAuthorChapterCreate(workId),
      data: _compact({
        'chapterNo': chapterNo,
        'chapterTitle': chapterTitle,
        'content': content,
        'isFree': isFree ? '1' : '0',
      }),
      parser: _mapParser,
    );
    final chapterId = _intOrNull(data?['chapterId']);
    if (chapterId == null) throw ApiException('新增章节失败');
    return chapterId;
  }

  /// 更新章节（B 套 PUT /content/chapters/{chapterId}）。
  ///
  /// 标题 / 正文 / 试读标记 / 隐藏状态均可选，null 表示不更新；wordCount 由后端重算。
  /// 至少需提供一个待更新字段，否则后端按 400 拒绝。
  Future<void> updateChapter(
    int chapterId, {
    String? chapterTitle,
    String? content,
    bool? isFree,
    String? status,
  }) async {
    await _api.put<Map<String, dynamic>>(
      ApiEndpoints.contentAuthorChapterById(chapterId),
      data: _compact({
        'chapterTitle': chapterTitle,
        'content': content,
        'isFree': isFree == null ? null : (isFree ? '1' : '0'),
        'status': status,
      }),
      parser: _mapParser,
    );
  }

  /// 删除章节（B 套 DELETE /content/chapters/{chapterId}，物理删除）。
  Future<void> deleteChapter(int chapterId) async {
    await _api.delete<Map<String, dynamic>>(
      ApiEndpoints.contentAuthorChapterById(chapterId),
      parser: _mapParser,
    );
  }

  /// 审核记录列表（审核历史 + 管理员意见）。
  Future<List<ReviewRecordItem>> reviewRecords(int workId) async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.authorWorkReviewRecords(workId),
      parser: _listParser,
    );
    return _mapItems(data, ReviewRecordItem.fromJson);
  }

  static List<dynamic> _listParser(dynamic raw) =>
      raw is List ? raw : const <dynamic>[];

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static List<T> _mapItems<T>(
    List<dynamic>? raw,
    T Function(Map<String, dynamic> item) parser,
  ) {
    if (raw == null) return <T>[];
    return raw
        .whereType<Map>()
        .map((e) => parser(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 去掉空值字段：后端按「字段缺失 = 不更新」处理，传空串会变成无效条件。
  static Map<String, dynamic> _compact(Map<String, dynamic> raw) {
    final body = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      body[key] = value;
    });
    return body;
  }

  static int? _intOrNull(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) return int.tryParse(value);
    return null;
  }
}