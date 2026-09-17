/// 分页结果通用模型（列表接口普遍返回 `{ total, list: [...] }`）。
class PagedResult<T> {
  const PagedResult({required this.total, required this.list});

  final int total;
  final List<T> list;

  bool get isEmpty => list.isEmpty;

  factory PagedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) itemParser,
  ) {
    final rawList = json['list'];
    return PagedResult<T>(
      total: (json['total'] as num?)?.toInt() ?? 0,
      list: rawList is List
          ? rawList
              .map((e) => itemParser(Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
    );
  }
}
