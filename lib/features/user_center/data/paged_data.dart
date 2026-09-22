/// A5 分页数据与解析（App 用户域统一 `{total, list}` 载荷）。
class PagedData<T> {
  const PagedData({required this.total, required this.list});

  final int total;
  final List<T> list;

  bool get isEmpty => list.isEmpty;

  static PagedData<T> parse<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) itemParser,
  ) {
    final raw = json['list'];
    return PagedData<T>(
      total: (json['total'] as num?)?.toInt() ?? 0,
      list: raw is List
          ? raw.whereType<Map>().map((e) => itemParser(Map<String, dynamic>.from(e))).toList()
          : const [],
    );
  }
}
