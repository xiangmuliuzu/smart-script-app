import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 结构化回跳意图（规格 §8.1）。
///
/// [target] 是**解析后的定位串**（path + query），例如
/// `/profile/messages/detail?id=12`。用定位串而不是命名路由 + 参数对象，
/// 是因为定位串天然可序列化、可由路由框架直接消费，也不需要为每种路由
/// 单独维护参数还原逻辑；命名路由仍由 [RouteName] 统一登记。
class RouteIntent {
  const RouteIntent(this.target);

  final String target;

  /// 登录页参数名：登录成功后读取并消费一次。
  static const String paramName = 'redirect';

  /// 取自 URI 查询参数；空白或超长视为无效意图。
  ///
  /// 长度上限用于挡住被构造的超长回跳串，避免把登录页变成任意跳转入口。
  static const int maxLength = 512;

  static RouteIntent? fromParam(String? raw) {
    if (raw == null) return null;
    final value = Uri.decodeComponent(raw).trim();
    if (value.isEmpty || value.length > maxLength) return null;
    // 只接受站内绝对路径（防止开放重定向到外部地址）
    if (!value.startsWith('/')) return null;
    if (value.startsWith('//')) return null;
    return RouteIntent(value);
  }

  String get encoded => Uri.encodeComponent(target);
}

/// 回跳意图存储：登录成功消费一次，主动退出清空（规格 §8.1）。
class RouteIntentStore {
  RouteIntent? _pending;

  RouteIntent? get pending => _pending;

  void save(RouteIntent intent) {
    _pending = intent;
  }

  /// 消费一次：取出即清空，保证同一个意图不会被重复回跳。
  RouteIntent? consume() {
    final intent = _pending;
    _pending = null;
    return intent;
  }

  void clear() {
    _pending = null;
  }
}

final routeIntentStoreProvider = Provider<RouteIntentStore>((ref) => RouteIntentStore());
