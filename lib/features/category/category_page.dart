import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../bookstore/data/bookstore_models.dart';
import '../bookstore/data/content_providers.dart';

/// 分类页（参考番茄小说标签墙布局）。
///
/// 顶部：频道 Tab（男生 / 女生），切换时重新加载对应频道标签
/// 左侧：维度导航（热门标签 / 主题 / 角色 / 情节），滚动联动高亮
/// 右侧：所有维度标签按区块堆叠展示，每区块可展开/收起
class CategoryPage extends ConsumerStatefulWidget {
  const CategoryPage({super.key});

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage> {
  int? _selectedChannelId;
  int _currentDimensionIndex = 0;
  final _scrollController = ScrollController();
  final _dimensionKeys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_dimensionKeys.isEmpty) return;
    // 滚动区域顶部的位置
    final screenTop = MediaQuery.of(context).padding.top + kToolbarHeight + 46;
    final screenBottom = MediaQuery.of(context).size.height;
    int newIndex = 0;
    double minDy = double.infinity;
    // 找所有在屏幕可见范围内的区块里，最靠上的那个（和番茄逻辑一致）
    for (int i = 0; i < _dimensionKeys.length; i++) {
      final ctx = _dimensionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox;
      final dy = box.localToGlobal(Offset.zero).dy;
      // 只看顶部还在屏幕里的区块（没完全滚出屏幕顶部，也没完全在屏幕下面）
      if (dy < screenBottom && dy + box.size.height > screenTop) {
        if (dy < minDy) {
          minDy = dy;
          newIndex = i;
        }
      }
    }
    if (newIndex != _currentDimensionIndex) {
      setState(() => _currentDimensionIndex = newIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navAsync = ref.watch(categoryNavProvider(_selectedChannelId));

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('分类'),
        backgroundColor: AppColors.pageBackground,
        actions: [
          IconButton(
            onPressed: () => context.push(RoutePath.search),
            icon: const Icon(Icons.search),
            tooltip: '搜索',
          ),
        ],
      ),
      body: navAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(categoryNavProvider),
            child: const Text('重试', style: TextStyle(fontSize: 13)),
          ),
        ),
        data: (nav) {
          if (nav.channels.isEmpty) {
            return const Center(
              child: Text(
                '暂无频道',
                style: TextStyle(fontSize: 13, color: AppColors.text3),
              ),
            );
          }

          // 初始化选中的频道ID
          if (_selectedChannelId == null) {
            _selectedChannelId = nav.channelId ?? nav.channels.first.channelId;
          }
          int safeChannelIdx = nav.channels
              .indexWhere((c) => c.channelId == _selectedChannelId);
          if (safeChannelIdx < 0) safeChannelIdx = 0;

          // 初始化维度key
          if (_dimensionKeys.length != nav.dimensions.length) {
            _dimensionKeys
              ..clear()
              ..addAll(nav.dimensions.map((_) => GlobalKey()));
            _currentDimensionIndex = 0;
          }

          return Column(
            children: [
              // 顶部频道 Tab
              _ChannelTabs(
                channels: [for (final c in nav.channels) c.channelName],
                current: safeChannelIdx,
                onChanged: (i) {
                  setState(() {
                    _selectedChannelId = nav.channels[i].channelId;
                    _currentDimensionIndex = 0;
                    _dimensionKeys.clear();
                  });
                },
              ),
              Expanded(
                child: nav.dimensions.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无标签维度',
                          style: TextStyle(fontSize: 13, color: AppColors.text3),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左侧维度导航栏
                          _DimensionNav(
                            dimensions: [for (final d in nav.dimensions) d.name],
                            currentIndex: _currentDimensionIndex,
                            onTap: (index) => _scrollToDimension(index),
                          ),
                          // 右侧标签区块堆叠：直接全部渲染，不用懒加载，彻底解决定位问题
                          Expanded(
                            child: Container(
                              color: AppColors.card,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = 0; i < nav.dimensions.length; i++)
                                      _DimensionSection(
                                        key: _dimensionKeys[i],
                                        dimension: nav.dimensions[i],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _scrollToDimension(int index) async {
    setState(() => _currentDimensionIndex = index);
    if (index < 0 || index >= _dimensionKeys.length) return;
    // 如果目标区块还没渲染，先滚动到底部触发渲染，再等一帧定位
    final key = _dimensionKeys[index];
    var ctx = key.currentContext;
    if (ctx == null) {
      // 先快速滚一段距离，让目标区块进入渲染范围
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent * (index / (_dimensionKeys.length - 1)),
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      // 等一帧让widget渲染完成
      await Future.delayed(const Duration(milliseconds: 50));
      ctx = key.currentContext;
    }
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.0,
      );
    }
  }
}

/// 顶部频道 Tab（男生 / 女生）。
class _ChannelTabs extends StatelessWidget {
  const _ChannelTabs({
    required this.channels,
    required this.current,
    required this.onChanged,
  });

  final List<String> channels;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.pageBackground,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < channels.length; i++)
            Expanded(
              child: _TabItem(
                label: channels[i],
                selected: i == current,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: selected ? 16 : 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? AppColors.text1 : AppColors.text2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 3,
            width: 28,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 左侧维度导航栏（热门标签 / 主题 / 角色 / 情节）。
/// 带选中态高亮：左侧竖条 + 橙色文字
class _DimensionNav extends StatelessWidget {
  const _DimensionNav({
    required this.dimensions,
    required this.currentIndex,
    required this.onTap,
  });

  final List<String> dimensions;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      color: AppColors.pageBackground,
      child: ListView.builder(
        itemCount: dimensions.length,
        itemBuilder: (context, index) {
          final selected = index == currentIndex;
          return InkWell(
            onTap: () => onTap(index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              child: Row(
                children: [
                  // 选中态左侧竖条
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dimensions[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? AppColors.primary : AppColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 单个维度区块（可展开/收起）。
class _DimensionSection extends StatefulWidget {
  const _DimensionSection({super.key, required this.dimension});

  final NavDimension dimension;

  @override
  State<_DimensionSection> createState() => _DimensionSectionState();
}

class _DimensionSectionState extends State<_DimensionSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final allItems = <NavItem>[];
    for (final group in widget.dimension.groups) {
      allItems.addAll(group.items);
    }

    // 默认显示前 10 行（30个），展开显示全部
    final visibleItems = _expanded ? allItems : allItems.take(30).toList();
    final hasMore = allItems.length > 30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 区块标题 + 展开按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.dimension.name,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.text3,
              ),
            ),
            if (hasMore)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Text(
                      _expanded ? '收起' : '展开',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text3,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppColors.text3,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // 标签 chips 网格：3列，紧凑间距
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in visibleItems)
              _TagChip(
                label: item.itemName,
                onTap: () => context.push(
                  RoutePath.workListUrl(tagId: item.itemId, title: item.itemName),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 标签 chip（大圆角矩形，3列布局）。
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.pageBackground,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: (MediaQuery.of(context).size.width - 88 - 48 - 20) / 3,
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.text1),
          ),
        ),
      ),
    );
  }
}
