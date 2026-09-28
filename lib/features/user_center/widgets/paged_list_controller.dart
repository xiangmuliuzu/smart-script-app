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

  /// 触底追加失败的原因（非空时 footer 显示提示与重试，已加载数据不动）。
  /// 首屏错误用 [error]；两者互不覆盖。
  String? loadMoreError;
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
    loadMoreError = null;
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
    if (loadMoreError != null) return; // 失败驻留时不再自动重试，等 [retryLoadMore]
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
    } catch (e) {
      // 追加失败不覆盖首屏结果：保留已加载数据与分页游标，给出明确提示与重试。
      // 刷新或切换筛选已使本请求作废时（generation 变化），失败不得覆盖新列表状态。
      if (generation != _generation) return;
      loadMoreError = e is Exception ? _messageOf(e) : '加载失败，请稍后重试';
    } finally {
      // loadingMore 是本调用自身的在途标记，无条件复位；
      // 通知仍按代际收敛，过期代际的 UI 状态由当次 load 负责刷新。
      loadingMore = false;
      if (generation == _generation) {
        notifyListeners();
      }
    }
  }

  /// 触底失败后的重试：按同一页码重取（失败时未曾追加，天然无重复项）。
  Future<void> retryLoadMore() async {
    if (loading || loadingMore) return;
    loadMoreError = null;
    notifyListeners();
    await loadMore();
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
