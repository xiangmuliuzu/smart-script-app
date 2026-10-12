import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';

/// 公告 ID 与站内消息 ID 分开处理，PC 与 App 共用后台公告读取契约。
class AnnouncementItem {
  const AnnouncementItem(
      {required this.noticeId,
      required this.title,
      this.type = '2',
      this.content,
      this.createdAt,
      this.read = false});
  final int noticeId;
  final String title;
  final String type;
  final String? content;
  final String? createdAt;
  final bool read;
  String get typeLabel => '公告';

  factory AnnouncementItem.fromJson(Map<String, dynamic> json) =>
      AnnouncementItem(
        noticeId: (json['noticeId'] as num?)?.toInt() ?? 0,
        title: json['noticeTitle'] as String? ?? '',
        type: json['noticeType'] as String? ?? '2',
        content: json['noticeContent'] as String?,
        createdAt: json['createTime'] as String?,
        read: json['isRead'] as bool? ?? false,
      );
}

class AnnouncementRepository {
  AnnouncementRepository(this._api);
  final ApiClient _api;
  static const _prefix = '/announcements';

  Future<PagedData<AnnouncementItem>> list(
      {int pageNum = 1, int pageSize = 10}) async {
    final data = await _api.get<Map<String, dynamic>>(_prefix,
        query: {'pageNum': pageNum, 'pageSize': pageSize}, parser: _map);
    if (data == null) throw ApiException('公告加载失败');
    return PagedData.parse(data, AnnouncementItem.fromJson);
  }

  Future<AnnouncementItem> detail(int id) async {
    final data =
        await _api.get<Map<String, dynamic>>('$_prefix/$id', parser: _map);
    if (data == null || data.isEmpty) throw ApiException('公告不存在或已关闭');
    return AnnouncementItem.fromJson(data);
  }

  Future<int> unreadCount() async {
    final data = await _api.get<Map<String, dynamic>>('$_prefix/unread-count',
        parser: _map);
    final total = data?['total'];
    if (total is! int || total < 0) throw ApiException('未读统计暂不可用');
    return total;
  }

  Future<void> markRead(int id) async {
    await _api.put('$_prefix/$id/read');
  }

  Future<void> markAllRead() async {
    await _api.put('$_prefix/read-all');
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((key, value) => MapEntry('$key', value));
    throw ApiException('公告响应无效');
  }
}
