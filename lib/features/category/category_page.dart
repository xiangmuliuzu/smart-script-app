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
///
/// 频道切换的过渡：
/// - Tab 文案与底部指示条做隐式补间，不再是瞬间跳变；
/// - 新频道数据到达前继续展示旧内容，不会先清空成 loading；
/// - 新内容淡出淡入 + 轻微上滑，播放期间保留可滚动布局，滚动条不抖动；
/// - 每个频道各自记住滚动位置与维度高亮，切回时原地恢复。
class CategoryPage extends ConsumerStatefulWidget {
  const CategoryPage({super.key});

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage> {
  int? _selectedChannelId;

  /// 各频道的导航数据缓存：切回看过的频道时直接出内容，不再闪一次加载态。
  final Map<int?, CategoryNav> _navCache = {};

  /// 各频道的滚动位置：切回频道时回到离开时的位置。
  final Map<int?, double> _scrollOffsets = {};

  /// 正在展示的数据与它所属的频道（切换加载期间仍是上一个频道的内容）。
  CategoryNav? _shownNav;
  int? _shownChannelId;

  /// 频道列表里对应 [channelId] 的下标；找不到时回落到数据自带频道，再回落第一个。
  int _channelIndexOf(CategoryNav nav, [int? channelId]) {
    final id = channelId ?? _selectedChannelId;
    var index = nav.channels.indexWhere((c) => c.channelId == id);
    if (index < 0) {
      index = nav.channels.indexWhere((c) => c.channelId == nav.channelId);
    }
    return index < 0 ? 0 : index;
  }

  void _selectChannel(CategoryNav nav, int index) {
    final channelId = nav.channels[index].channelId;
    if (channelId == _selectedChannelId) return;
    setState(() => _selectedChannelId = channelId);
  }

  @override
  Widget build(BuildContext context) {
    final navAsync = ref.watch(categoryNavProvider(_selectedChannelId));

    // 新频道数据到达：先把"当前频道"定下来，再按请求参数与实际频道各缓存一份，
    // 切回看过的频道时能立刻出内容，不再闪一次 loading。
    final latest = navAsync.valueOrNull;
    if (latest != null) {
      _selectedChannelId ??= latest.channelId ??
          (latest.channels.isNotEmpty ? latest.channels.first.channelId : null);
      _navCache[_selectedChannelId] = latest;
      if (latest.channelId != null) _navCache[latest.channelId] = latest;
    }

    // 本次选中频道的缓存；没命中时沿用上一个频道的内容，等新数据落位再换。
    final target = _navCache[_selectedChannelId];
    final nav = target ?? _shownNav;
    // 展示内容换人时同步它所属的频道：后端没回 channelId 时回落到请求用的频道，
    // 否则钥匙不变，AnimatedSwitcher 就不会做淡出淡入。
    if (nav != null && !identical(nav, _shownNav)) {
      _shownNav = nav;
      _shownChannelId =
          identical(nav, latest) ? (latest!.channelId ?? _selectedChannelId) : _selectedChannelId;
    }
    // 目标频道没有缓存且请求失败时才让位给错误态，避免把旧内容当成新频道。
    final failed = navAsync.hasError && target == null;

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
      body: nav == null || failed
          ? navAsync.when(
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
              data: (_) => const SizedBox.shrink(),
            )
          : _buildContent(nav),
    );
  }

  Widget _buildContent(CategoryNav nav) {
    if (nav.channels.isEmpty) {
      return const Center(
        child: Text(
          '暂无频道',
          style: TextStyle(fontSize: 13, color: AppColors.text3),
        ),
      );
    }

    // Tab 高亮跟随"已点击的频道"，内容则等数据到位后再淡入，两者不会打架。
    final current = _channelIndexOf(nav);
    // 固定本次构建的频道：淡出中的旧视图回调时，不能把它的滚动位置写到新频道名下。
    final shownId = _shownChannelId;

    return Column(
      children: [
        // 顶部频道 Tab
        _ChannelTabs(
          channels: [for (final c in nav.channels) c.channelName],
          current: current,
          onChanged: (i) => _selectChannel(nav, i),
        ),
        Expanded(
          child: nav.dimensions.isEmpty
              ? const Center(
                  child: Text(
                    '暂无标签维度',
                    style: TextStyle(fontSize: 13, color: AppColors.text3),
                  ),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  reverseDuration: const Duration(milliseconds: 170),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  // 位移只放在淡入淡出里：过渡期间仍是完整的可滚动布局，
                  // 滚动条不会因为内容被裁剪而闪一下。
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.012),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  child: _ChannelTags(
                    key: ValueKey<int?>(shownId),
                    dimensions: nav.dimensions,
                    initialOffset: _scrollOffsets[shownId] ?? 0,
                    onScrollChanged: (offset) => _scrollOffsets[shownId] = offset,
                  ),
                ),
        ),
      ],
    );
  }
}

/// 顶部频道 Tab（男生 / 女生）。
///
/// 文案大小 / 字重 / 颜色，以及底部指示条宽度，都用隐式动画补间，
/// 切换时不再瞬间跳变。
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

  static const Duration _duration = Duration(milliseconds: 220);
  static const Curve _curve = Curves.easeOutCubic;

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
          AnimatedDefaultTextStyle(
            duration: _duration,
            curve: _curve,
            style: TextStyle(
              fontSize: selected ? 16 : 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? AppColors.text1 : AppColors.text2,
            ),
            child: Text(label),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: _duration,
            curve: _curve,
            height: 3,
            // 宽度从 0 长到 28：指示条随文字一起"长出来"，而不是整条闪现
            width: selected ? 28 : 0,
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

/// 某个频道的标签墙：左侧维度导航 + 右侧标签区块堆叠。
///
/// 每个频道各自持有一份滚动位置与维度高亮，切换频道不会串台。
class _ChannelTags extends StatefulWidget {
  const _ChannelTags({
    super.key,
    required this.dimensions,
    required this.initialOffset,
    required this.onScrollChanged,
  });

  final List<NavDimension> dimensions;

  /// 挂载时恢复的滚动位置（切回看过的频道时是离开时的位置）。
  final double initialOffset;

  /// 滚动位置变化回调，供父级按频道记忆位置。
  final ValueChanged<double> onScrollChanged;

  @override
  State<_ChannelTags> createState() => _ChannelTagsState();
}

class _ChannelTagsState extends State<_ChannelTags> {
  int _currentDimensionIndex = 0;
  late final ScrollController _scrollController;
  final _dimensionKeys = <GlobalKey>[];

  /// "跳到某个维度"的补间进行中：此时暂停滚动联动，免得高亮被中途位置抢走。
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _dimensionKeys.addAll(widget.dimensions.map((_) => GlobalKey()));
    _scrollController =
        ScrollController(initialScrollOffset: widget.initialOffset);
    _scrollController.addListener(_onScroll);
    // 恢复的滚动位置要等首帧布局后才能换算左侧高亮；
    // 频道的标签变少了导致旧位置越界时，先收紧到可滚动范围内。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (_scrollController.offset > max) _scrollController.jumpTo(max);
      _onScroll();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (!_jumping) _syncDimensionIndex();
    widget.onScrollChanged(_scrollController.offset);
  }

  void _syncDimensionIndex() {
    if (_dimensionKeys.isEmpty) return;
    // 滚动区域顶部的位置
    final screenTop = MediaQuery.of(context).padding.top + kToolbarHeight + 46;
    int newIndex = 0;
    // 从第一个维度开始遍历，哪个维度的标题滚到顶部线以下就更新，最后一个就是当前高亮
    for (int i = 0; i < _dimensionKeys.length; i++) {
      final ctx = _dimensionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox;
      final dy = box.localToGlobal(Offset.zero).dy;
      // 标题到达顶部线位置，就把它设为当前维度
      if (dy <= screenTop + 10) {
        newIndex = i;
      }
    }
    // 已经滚到最底部，直接高亮最后一个维度（情节）
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 20) {
      newIndex = _dimensionKeys.length - 1;
    }
    if (newIndex != _currentDimensionIndex) {
      setState(() => _currentDimensionIndex = newIndex);
    }
  }

  Future<void> _scrollToDimension(int index) async {
    if (index < 0 || index >= _dimensionKeys.length) return;
    if (index == _currentDimensionIndex) return;
    final ctx = _dimensionKeys[index].currentContext;
    if (ctx == null) return;
    _jumping = true;
    setState(() => _currentDimensionIndex = index);
    try {
      // 用缓动的定位补间替换原来的"瞬移 + 恢复"两段式
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        alignment: 0.0,
      );
    } finally {
      _jumping = false;
      if (mounted) _syncDimensionIndex();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧维度导航栏
        _DimensionNav(
          dimensions: [for (final d in widget.dimensions) d.name],
          currentIndex: _currentDimensionIndex,
          onTap: _scrollToDimension,
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
                  for (var i = 0; i < widget.dimensions.length; i++)
                    _DimensionSection(
                      key: _dimensionKeys[i],
                      dimension: widget.dimensions[i],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 左侧维度导航栏（热门标签 / 主题 / 角色 / 情节）。
/// 带选中态高亮：左侧竖条 + 深色文字
class _DimensionNav extends StatelessWidget {
  const _DimensionNav({
    required this.dimensions,
    required this.currentIndex,
    required this.onTap,
  });

  static const Duration _duration = Duration(milliseconds: 200);
  static const Curve _curve = Curves.easeOutCubic;

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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              child: Row(
                children: [
                  // 选中态左侧竖条：高度从 0 长到 16，像从中间"长"出来
                  AnimatedContainer(
                    duration: _duration,
                    curve: _curve,
                    width: 3,
                    height: selected ? 16 : 0,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: _duration,
                      curve: _curve,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? AppColors.text1 : AppColors.text3,
                      ),
                      child: Text(dimensions[index]),
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
                    // 箭头翻转而不是换图标，展开/收起的动作连成一条
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // 标签 chips 网格：3列，紧凑间距；展开/收起时高度补间而非整块跳变
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in visibleItems)
                _TagChip(
                  label: item.itemName,
                  onTap: () => context.push(
                    RoutePath.workListUrl(
                      tagId: item.itemId,
                      title: item.itemName,
                    ),
                  ),
                ),
            ],
          ),
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
