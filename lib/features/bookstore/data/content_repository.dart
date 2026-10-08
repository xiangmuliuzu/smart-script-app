import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'bookstore_models.dart';

/// B 模块书城数据层（内容与作品）。
///
/// 只做三件事：拼查询参数、解析 App 信封里的 `data`、把 JSON 映射成页面模型。
/// 鉴权与 Token 由 [ApiClient] 统一处理；书城浏览链路全部对游客开放，不需要登录态。
class ContentRepository {
  ContentRepository(this._api);

  final ApiClient _api;

  /// 首页 Banner 轮播（后端只返回已启用且在展示时间窗内的 Banner）。
  Future<List<BannerItem>> listBanners({String? position}) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentBanners,
      query: _compact({'position': position}),
      parser: _mapParser,
    );
    return _items(data, BannerItem.fromJson);
  }

  /// 分类列表；[parentId] 传 0 取顶级分类，[categoryType] 用于限定分类用途。
  Future<List<CategoryItem>> listCategories({String? categoryType, int? parentId}) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentCategories,
      query: _compact({'categoryType': categoryType, 'parentId': parentId}),
      parser: _mapParser,
    );
    return _items(data, CategoryItem.fromJson);
  }

  /// 标签列表（后端按使用量降序下发）。
  Future<List<TagItem>> listTags({String? tagType}) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentTags,
      query: _compact({'tagType': tagType}),
      parser: _mapParser,
    );
    return _items(data, TagItem.fromJson);
  }

  /// 作品列表（分页 + 筛选 + 排序）。
  ///
  /// [sort] 为空时由后端回落 `latest`；非法值同样回落，客户端不需要做白名单校验。
  Future<PagedData<BookItem>> pageWorks({
    int? categoryId,
    int? tagId,
    String? keyword,
    String? sort,
    required int pageNum,
    required int pageSize,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorks,
      query: _compact({
        'categoryId': categoryId,
        'tagId': tagId,
        'keyword': keyword,
        'sort': sort,
        'page': pageNum,
        'pageSize': pageSize,
      }),
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取作品列表失败');
    return PagedData.parse<BookItem>(data, BookItem.fromJson);
  }

  /// 作品详情；未上架或不存在时后端按 404 拒绝，由 [ApiClient] 抛 [ApiException]。
  Future<BookItem> workDetail(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkById(workId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取作品详情失败');
    return BookItem.fromJson(data);
  }

  /// 作品章节目录；payload 附带作品试读配置，目录页无需再取详情。
  ///
  /// [ChapterSummary.readable] 由服务端按试读范围判定，客户端不自行推算。
  Future<ChapterListPayload> listChapters(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkChapters(workId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取章节目录失败');
    return ChapterListPayload.fromJson(data);
  }

  /// 章节正文；超出试读范围时后端返回 code=403 且 data 不含 content，
  /// 由 [ApiClient] 抛 [ApiException]，阅读页据此展示「试读结束」提示。
  Future<ChapterDetail> chapterDetail(int chapterId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentChapter(chapterId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取章节正文失败');
    return ChapterDetail.fromJson(data);
  }

  /// 作品试读包：可读章节 + 试读文件（游客可读）。
  Future<PreviewPayload> workPreview(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkPreview(workId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取试读内容失败');
    return PreviewPayload.fromJson(data);
  }

  /// 版权合作联系方式：只返回「是否登记 + 展示范围」，不含明文联系方式。
  Future<WorkContact> workContact(int workId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorkContact(workId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取合作联系方式失败');
    return WorkContact.fromJson(data);
  }

  /// 作品榜单；[type] 取 view/favorite/sale/rating，空值由后端回落 view。
  Future<List<RankingItem>> listRankings({String? type, int? limit}) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentRankings,
      query: _compact({'type': type, 'limit': limit}),
      parser: _mapParser,
    );
    return _items(data, RankingItem.fromJson);
  }

  /// 我的书架；需 App Token，归属由服务端身份决定。
  Future<ShelfPayload> shelf() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentShelf,
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('获取书架失败');
    return ShelfPayload.fromJson(data);
  }

  /// 搜索历史列表（需 App Token，接口 2.7.4）。
  ///
  /// 后端按最近搜索时间倒序下发最近若干条（不做分页），故无 total。
  Future<List<SearchHistoryItem>> listSearchHistory() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentSearchHistory,
      parser: _mapParser,
    );
    return _items(data, SearchHistoryItem.fromJson);
  }

  /// 记录搜索历史（需 App Token）。
  ///
  /// 契约未定义写入接口，按 sys_search_history 表补齐；同关键词已存在时
  /// 由后端合并计数并刷新时间。关键词长度上限由后端校验（超 100 字按 400 拒绝）。
  Future<void> recordSearchHistory(String keyword) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentSearchHistory,
      data: {'keyword': keyword},
      parser: _mapParser,
    );
  }

  /// 删除单条搜索历史（需 App Token，接口 2.7.5）；不存在或非本人时后端按 404 拒绝。
  Future<void> removeSearchHistory(int id) async {
    await _api.delete<Map<String, dynamic>>(
      ApiEndpoints.contentSearchHistoryById(id),
      parser: _mapParser,
    );
  }

  /// 清空全部搜索历史（需 App Token，接口 2.7.6）；无历史时为幂等成功。
  Future<void> clearSearchHistory() async {
    await _api.delete<Map<String, dynamic>>(
      ApiEndpoints.contentSearchHistory,
      parser: _mapParser,
    );
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  /// 去掉空值参数：后端按「参数缺失 = 不过滤」处理，传空串会变成无效条件。
  static Map<String, dynamic> _compact(Map<String, dynamic> raw) {
    final query = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      query[key] = value;
    });
    return query;
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
}

/// 后端下发的身份摘要（规格 §10：身份由服务端提供，客户端不自行拼装）。
class IdentitySummary {
  const IdentitySummary({
    required this.authenticated,
    required this.guest,
    this.userId,
    this.accountType,
    this.realNameStatus = 'NOT_SUBMITTED',
    this.authorCapability = false,
    this.roleCodes = const [],
    this.permissionCodes = const [],
  });

  final bool authenticated;
  final bool guest;
  final int? userId;
  final String? accountType;
  final String realNameStatus;
  final bool authorCapability;
  final List<String> roleCodes;
  final List<String> permissionCodes;

  factory IdentitySummary.fromJson(Map<String, dynamic> json) => IdentitySummary(
        authenticated: json['authenticated'] as bool? ?? false,
        guest: json['guest'] as bool? ?? true,
        userId: (json['userId'] as num?)?.toInt(),
        accountType: json['accountType'] as String?,
        realNameStatus: json['realNameStatus'] as String? ?? 'NOT_SUBMITTED',
        authorCapability: json['authorCapability'] as bool? ?? false,
        roleCodes: (json['roleCodes'] as List?)?.whereType<String>().toList() ?? const [],
        permissionCodes:
            (json['permissionCodes'] as List?)?.whereType<String>().toList() ?? const [],
      );
}

/// 书架作品条目（书架接口尚未迁到真实库，批次 3 替换为 BookItem）。
class WorkItem {
  const WorkItem({
    required this.workId,
    required this.title,
    required this.authorName,
    required this.category,
    required this.wordCount,
    required this.freeToRead,
  });

  final int workId;
  final String title;
  final String authorName;
  final String category;
  final int wordCount;
  final bool freeToRead;

  factory WorkItem.fromJson(Map<String, dynamic> json) => WorkItem(
        workId: (json['workId'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        authorName: json['authorName'] as String? ?? '',
        category: json['category'] as String? ?? '',
        wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
        freeToRead: json['freeToRead'] as bool? ?? false,
      );
}

class ShelfPayload {
  const ShelfPayload({
    required this.identity,
    required this.works,
    required this.downloadable,
    required this.realNameRequired,
  });

  final IdentitySummary identity;
  final List<WorkItem> works;

  /// 是否可下载素材：由实名状态决定（业务准入），与角色无关。
  final bool downloadable;
  final bool realNameRequired;

  factory ShelfPayload.fromJson(Map<String, dynamic> json) {
    final rawWorks = json['works'];
    return ShelfPayload(
      identity: IdentitySummary.fromJson(
        json['identity'] is Map ? Map<String, dynamic>.from(json['identity'] as Map) : const {},
      ),
      works: rawWorks is List
          ? rawWorks.whereType<Map>().map((e) => WorkItem.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      downloadable: json['downloadable'] as bool? ?? false,
      realNameRequired: json['realNameRequired'] as bool? ?? true,
    );
  }
}