import 'package:flutter/foundation.dart';

import '../../user_center/data/paged_data.dart';
import 'trade_models.dart';

/// 任务列表分页器（与渲染方式无关的累积逻辑）。
///
/// 广场页（CustomScrollView sliver）与"我的任务"页（ListView）共用同一套
/// 「首屏加载 / 触底加载更多 / 是否还有更多 / 错误重试」状态机，避免分页逻辑两处漂移。
/// 由页面持有一个实例，通过 [_loader] 回调注入具体查询（页面从当前筛选态组装参数）。
class DemandPager extends ChangeNotifier {
  DemandPager(this._loader, {this.pageSize = 20});

  /// 拉取第 [pageNum] 页（1 起）。由页面提供，内部读取当前筛选条件。
  final Future<PagedData<DemandTask>> Function(int pageNum) _loader;

  final int pageSize;

  final List<DemandTask> items = <DemandTask>[];
  int total = 0;

  bool loading = false; // 首屏 / 重置加载中
  bool loadingMore = false; // 追加加载中
  bool hasMore = true;
  Object? error;

  int _pageNum = 0;

  /// 请求代次：每次 reset() 自增。异步响应返回时代次不一致即丢弃，
  /// 防止快速切换筛选时旧筛选的 page1/下一页晚到污染当前列表（竞态）。
  int _gen = 0;

  /// 是否已加载过（用于区分"首屏空态"与"筛选后无结果"）。
  bool get loaded => _pageNum > 0 || error != null;

  /// 重新从第一页加载（筛选变化、下拉刷新、编辑/接单后调用）。
  Future<void> reset() async {
    final gen = ++_gen;
    loading = true;
    loadingMore = false; // 作废在飞的追加加载（其回包因代次不符会被丢弃）
    error = null;
    hasMore = true;
    _pageNum = 0;
    notifyListeners();
    await _fetch(1, replace: true, gen: gen);
    if (gen != _gen) return; // 已有更新的 reset 发起，不覆盖新状态
    loading = false;
    notifyListeners();
  }

  /// 触底加载下一页。
  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;
    final gen = _gen;
    loadingMore = true;
    notifyListeners();
    await _fetch(_pageNum + 1, replace: false, gen: gen);
    if (gen != _gen) return; // 筛选已变，丢弃
    loadingMore = false;
    notifyListeners();
  }

  Future<void> _fetch(int page, {required bool replace, required int gen}) async {
    try {
      final paged = await _loader(page);
      if (gen != _gen) return; // 过期响应：不污染当前筛选的列表/总数
      if (replace) items.clear();
      items.addAll(paged.list);
      total = paged.total;
      _pageNum = page;
      hasMore = items.length < total && paged.list.isNotEmpty;
      error = null;
    } catch (e) {
      if (gen != _gen) return;
      error = e;
      if (replace) {
        items.clear();
        total = 0;
      }
      hasMore = false;
    }
  }
}
