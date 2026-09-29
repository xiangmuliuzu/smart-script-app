import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

/// A6 示例业务数据层（B 模块：内容/书城）。
///
/// 演示下游模块如何消费统一身份：
///   - 页面只调用本仓库，不直接接触 Dio / Token；
///   - `works` 为公开接口，游客可读，响应里的 identity 摘要用于展示登录态；
///   - `shelf` 为受保护接口，未登录会被后端拒绝（401），因此调用前必须过守卫。
class ContentRepository {
  ContentRepository(this._api);

  final ApiClient _api;

  /// 公开作品列表；返回作品与身份摘要（游客时 authenticated=false、userId 为空）。
  Future<WorksPayload> listWorks() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentWorks,
      parser: _mapParser,
    );
    return WorksPayload.fromJson(data ?? const {});
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

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}

/// 作品摘要（字段与后端示例模型一致；内容表确定后随契约调整）。
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

class WorksPayload {
  const WorksPayload({
    required this.identity,
    required this.works,
    required this.personalized,
  });

  final IdentitySummary identity;
  final List<WorkItem> works;
  final bool personalized;

  factory WorksPayload.fromJson(Map<String, dynamic> json) {
    final rawWorks = json['works'];
    return WorksPayload(
      identity: IdentitySummary.fromJson(
        json['identity'] is Map ? Map<String, dynamic>.from(json['identity'] as Map) : const {},
      ),
      works: rawWorks is List
          ? rawWorks.whereType<Map>().map((e) => WorkItem.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      personalized: json['personalized'] as bool? ?? false,
    );
  }
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
