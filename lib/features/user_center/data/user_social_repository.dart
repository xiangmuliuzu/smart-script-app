import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'user_social_models.dart';

/// A5 个人主页与关注数据访问（§1.7）。
///
/// 关注/粉丝/获赞均来自真实后端计数；获赞走内容域统计端点，作品列表复用书城分页。
class UserSocialRepository {
  UserSocialRepository(this._api);

  final ApiClient _api;

  /// 指定用户的公开资料（含关注/粉丝/获赞计数与当前用户的关注态）。
  Future<UserProfileView> publicProfile(int userId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.userPublicProfile(userId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('用户不存在');
    var profile = UserProfileView.fromJson(data);
    // 获赞来自内容域统计端点（用户域不含作品数据），单独取一次并合并。
    try {
      final stats = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.userProfileStats(userId),
        parser: _mapParser,
      );
      final likeCount = (stats?['likeCount'] as num?)?.toInt() ?? 0;
      profile = profile.copyWith(likeCount: likeCount);
    } catch (_) {
      // 统计失败不影响主页主体展示，获赞留 0
    }
    return profile;
  }

  Future<List<UserSummary>> following(int userId) => _list(
        ApiEndpoints.userFollowing(userId),
      );

  Future<List<UserSummary>> followers(int userId) => _list(
        ApiEndpoints.userFollowers(userId),
      );

  /// 关注（幂等），返回是否发生变更与最新粉丝数。
  Future<FollowResult> follow(int userId) => _toggle(userId, follow: true);

  /// 取消关注（幂等）。
  Future<FollowResult> unfollow(int userId) => _toggle(userId, follow: false);

  /// 拉黑（幂等）；被拉黑方无法再发起询盘、会话、消息与关注。
  Future<bool> block(int userId) => _toggleBlock(userId, block: true);

  /// 解除拉黑（幂等）。
  Future<bool> unblock(int userId) => _toggleBlock(userId, block: false);

  /// 我拉黑的用户列表（公开字段）。
  Future<List<UserSummary>> blockedUsers() => _list(ApiEndpoints.myBlocks);

  Future<bool> _toggleBlock(int userId, {required bool block}) async {
    final path = ApiEndpoints.userBlock(userId);
    final data = block
        ? await _api.post<Map<String, dynamic>>(path, parser: _mapParser)
        : await _api.delete<Map<String, dynamic>>(path, parser: _mapParser);
    return data?['blocked'] as bool? ?? block;
  }

  Future<FollowResult> _toggle(int userId, {required bool follow}) async {
    final path = ApiEndpoints.userFollow(userId);
    final data = follow
        ? await _api.post<Map<String, dynamic>>(path, parser: _mapParser)
        : await _api.delete<Map<String, dynamic>>(path, parser: _mapParser);
    return FollowResult(
      following: data?['following'] as bool? ?? follow,
      followerCount: (data?['followerCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<UserSummary>> _list(String path) async {
    final data = await _api.get<Map<String, dynamic>>(path, parser: _mapParser);
    final raw = data?['list'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => UserSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}

/// 关注操作结果。
class FollowResult {
  const FollowResult({required this.following, required this.followerCount});

  final bool following;
  final int followerCount;
}
