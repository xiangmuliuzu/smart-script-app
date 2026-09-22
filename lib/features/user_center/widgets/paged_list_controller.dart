import 'package:flutter/material.dart';

import '../data/paged_data.dart';

/// A5 分页列表控制器（消息中心与反馈列表共用）。
///
/// 只做「首屏加载 + 触底追加 + 重试」三件事；筛选条件变化由页面调用 [reset]。
/// 抽离原因见 `rules.md` §3.2：消息与反馈两个列表的分页、空态、错误态逻辑一致，
/// 复制两份必然产生行为漂移。
class PagedListController<T> extends ChangeNotifier {
  PagedListController({required this.fetchPage, this.pageSize = 10});

  /// 拉取第 [pageNum] 页（从 1 开始）。
  final Future<PagedData<T>> Function(int pageNum, int pageSize) fetchPage;

  final int pageSize;

  final List<T> items = [];
  int total = 0;
  bool loading = false;
  bool loadingMore = false;
  String? error;
  bool _end = false;
  int _page = 0;
  int _generation = 0;

  bool get hasMore => !_end;
  bool get isEmpty => items.isEmpty;

  /// 首屏加载（或筛选变化后重新加载）。
  Future<void> load({bool refresh = false}) async {
    if (loading) return;
    final generation = ++_generation;
    if (refresh) {
      _page = 0;
      _end = false;
      items.clear();
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await fetchPage(1, pageSize);
      if (generation != _generation) return;
      items
        ..clear()
        ..addAll(data.list);
      total = data.total;
      _page = 1;
      _end = data.list.length >= data.total || data.list.isEmpty;
    } catch (e) {
      if (generation != _generation) return;
      error = e is Exception ? _messageOf(e) : '加载失败，请稍后重试';
      _end = true;
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// 触底追加下一页。
  Future<void> loadMore() async {
    if (loading || loadingMore || _end) return;
    final generation = _generation;
    loadingMore = true;
    notifyListeners();
    try {
      final data = await fetchPage(_page + 1, pageSize);
      if (generation != _generation) return;
      items.addAll(data.list);
      total = data.total;
      _page += 1;
      _end = data.list.isEmpty || items.length >= data.total;
    } catch (_) {
      // 追加失败不覆盖首屏结果，仅停止继续加载，用户可下拉刷新重试
      _end = true;
    } finally {
      if (generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  static String _messageOf(Object e) {
    final dynamic value = e;
    try {
      final message = value.message;
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {
      // 非 ApiException：走通用文案
    }
    return '加载失败，请稍后重试';
  }
}
