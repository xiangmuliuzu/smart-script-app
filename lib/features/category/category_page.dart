import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/common_views.dart';
import '../bookstore/data/bookstore_models.dart';
import '../bookstore/data/content_providers.dart';

/// 分类（B 模块，接口文档 2.10：分类列表 / 标签列表）。
///
/// 公开页，游客可读。数据复用书城契约：GET /content/categories（顶级）
/// 与 GET /content/tags，二者均已存在，故本页不新增后端接口。
///
/// 版式：左侧分组导航 + 右侧连续滚动的分组胶囊列表，两侧分组完全一致。
/// 左栏自上而下（剧本分类置顶）：
///   1. 剧本分类：顶级分类（sys_category.parent_id=0），点击 → 作品列表（?categoryId=）
///   2. 热门标签：全部标签（sys_tag，按 use_count 降序）
///   3. 题材 / 受众：按 sys_tag.tag_type 分组，点击 → 作品列表（?tagId=）
///
/// 右栏一次渲染全部分组（分组标题 + 3 列胶囊网格），可连续下滑浏览；
/// 左栏既是目录也是滚动指示器：点击定位到对应分组，手动下滑时高亮跟随。
/// 分组条目超过 3 行时支持展开 / 收起。
///
/// 分组口径全部来自既有字段，不新增表结构；后端新增 tag_type 时按原值兜底展示，
/// 不丢数据。
class CategoryPage extends ConsumerWidget {
  const CategoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final tagsAsync = ref.watch(tagsProvider(null));
    final error = categoriesAsync.error ?? tagsAsync.error;
    final ready = categoriesAsync.hasValue && tagsAsync.hasValue;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('分类'),
        actions: [
          IconButton(
            onPressed: () => context.push(RoutePath.search),
            icon: const Icon(Icons.search),
            tooltip: '搜索',
          ),
        ],
      ),
      body: !ready
          ? (error != null
              ? ErrorView(
                  message: error is ApiException ? error.message : '加载失败，请稍后重试',
                  onRetry: () => _refresh(ref),
                )
              : const LoadingView(message: '加载中'))
          : _CategoryBrowser(
              categories: categoriesAsync.valueOrNull!,
              tags: tagsAsync.valueOrNull!,
              onRefresh: () => _refresh(ref),
            ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(tagsProvider(null));
    await Future.wait<Object>([
      ref.read(categoriesProvider.future),
      ref.read(tagsProvider(null).future),
    ]);
  }
}

/// 标签类型展示名（sys_tag.tag_type）；后端新增类型时按原值兜底展示。
const Map<String, String> _tagTypeLabels = <String, String>{
  'theme': '题材',
  'audience': '受众',
};

/// 分组默认展示的胶囊数（3 列 × 3 行），超出部分折叠，点击「展开」查看全部。
const int _kCollapsedCount = 9;

/// 左侧导航栏宽度。
const double _kRailWidth = 88;

/// 分栏容器：左栏分组导航 + 右栏当前分组的胶囊网格。
class _CategoryBrowser extends StatefulWidget {
  const _CategoryBrowser({
    required this.categories,
    required this.tags,
    required this.onRefresh,
  });

  final List<CategoryItem> categories;
  final List<TagItem> tags;
  final Future<void> Function() onRefresh;

  @override
  State<_CategoryBrowser> createState() => _CategoryBrowserState();
}

class _CategoryBrowserState extends State<_CategoryBrowser> {
  /// 当前选中的分组下标（对应 [_groups] 的输出顺序）。
  int _selected = 0;

  /// 已手动展开的分组下标；未登记则按「超过 [_kCollapsedCount] 即折叠」展示。
  final Set<int> _expanded = <int>{};

  /// 右栏滚动控制器：手动下滑时驱动左栏高亮跟随。
  final ScrollController _scrollController = ScrollController();

  /// 右栏列表锚点，用于换算各分组相对列表顶部的偏移。
  final GlobalKey _listKey = GlobalKey();

  /// 各分组锚点，供左栏点击滚动定位；以分组下标为键，保证 key 稳定。
  final Map<int, GlobalKey> _sectionKeys = <int, GlobalKey>{};

  /// 左栏点击引发的程序化滚动期间锁住高亮，避免动画途中高亮扫过中间分组。
  bool _lockSpy = false;

  /// 分组总数（build 时刷新，供滚动监听判断是否已到底）。
  int _groupCount = 0;

  /// 分组顶部越过列表顶部该容差即视为当前分组。
  static const double _kActiveSlop = 4;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncSelection);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncSelection)
      ..dispose();
    super.dispose();
  }

  /// 滚动联动：取「顶部已越过列表顶部的最后一个分组」为当前项；到底时取末个分组。
  void _syncSelection() {
    if (_lockSpy) return;
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    var active = 0;
    _sectionKeys.forEach((index, key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final offset = box.localToGlobal(Offset.zero).dy - listTop;
      if (offset <= _kActiveSlop && index > active) active = index;
    });
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 1 && _groupCount > 1) {
      active = _groupCount - 1;
    }
    if (active != _selected) setState(() => _selected = active);
  }

  /// 左栏点击：滚动定位到对应分组，并在滚动结束后按实际位置校正高亮。
  Future<void> _select(int index) async {
    setState(() {
      _selected = index;
      _lockSpy = true;
    });
    final anchor = _sectionKeys[index]?.currentContext;
    if (anchor != null) {
      await Scrollable.ensureVisible(
        anchor,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0,
      );
    }
    if (!mounted) return;
    _lockSpy = false;
    _syncSelection();
  }

  /// 分组列表：剧本分类置顶，其后是标签域分组。
  List<_Group> _groups() {
    return <_Group>[
      if (widget.categories.isNotEmpty)
        _Group(
          label: '剧本分类',
          chips: [
            for (final category in widget.categories)
              _Chip(label: category.categoryName, categoryId: category.categoryId),
          ],
        ),
      if (widget.tags.isNotEmpty)
        _Group(
          label: '热门标签',
          // 热门口径即全量标签，不做折叠。
          collapsible: false,
          chips: [
            for (final tag in widget.tags) _Chip(label: tag.tagName, tagId: tag.tagId),
          ],
        ),
      ..._tagGroups(),
    ];
  }

  /// 按 tag_type 分组：已知类型按约定顺序输出，未知类型追加在后。
  Iterable<_Group> _tagGroups() sync* {
    final grouped = <String, List<TagItem>>{};
    for (final tag in widget.tags) {
      grouped.putIfAbsent(tag.tagType, () => <TagItem>[]).add(tag);
    }
    final orderedTypes = <String>[
      ..._tagTypeLabels.keys.where(grouped.containsKey),
      ...grouped.keys.where((type) => !_tagTypeLabels.containsKey(type)),
    ];
    for (final type in orderedTypes) {
      yield _Group(
        label: _tagTypeLabels[type] ?? (type.isEmpty ? '其他' : type),
        chips: [
          for (final tag in grouped[type]!)
            _Chip(label: tag.tagName, tagId: tag.tagId),
        ],
      );
    }
  }

  bool _isExpanded(int index, _Group group) =>
      !group.collapsible || _expanded.contains(index) || group.chips.length <= _kCollapsedCount;

  void _toggle(int index) {
    setState(() {
      if (!_expanded.remove(index)) _expanded.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    if (groups.isEmpty) {
      return const EmptyView(message: '暂无分类与标签', icon: Icons.category_outlined);
    }
    _groupCount = groups.length;
    final selected = _selected.clamp(0, groups.length - 1).toInt();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupRail(
          titles: [for (final item in groups) item.label],
          selectedIndex: selected,
          onSelect: _select,
        ),
        Expanded(
          child: Container(
            color: AppColors.card,
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ListView(
                key: _listKey,
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (var i = 0; i < groups.length; i++) _buildGroup(i, groups[i]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 单个分组：标题（含展开 / 收起）+ 胶囊网格；整块挂锚点供左栏滚动定位。
  Widget _buildGroup(int index, _Group group) {
    final expanded = _isExpanded(index, group);
    final visible =
        expanded ? group.chips : group.chips.take(_kCollapsedCount).toList(growable: false);
    return Column(
      key: _sectionKeys.putIfAbsent(index, () => GlobalKey()),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 8, 6),
          child: Row(
            children: [
              Text(
                group.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const Spacer(),
              if (group.collapsible && group.chips.length > _kCollapsedCount)
                _ExpandToggle(
                  expanded: expanded,
                  onTap: () => _toggle(index),
                ),
            ],
          ),
        ),
        _ChipGrid(
          chips: visible,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ],
    );
  }
}

/// 左侧分组导航：选中项主色加粗 + 左侧竖条。
class _GroupRail extends StatelessWidget {
  const _GroupRail({
    required this.titles,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> titles;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kRailWidth,
      color: AppColors.fill,
      child: ListView.builder(
        // 与右栏的 ListView 并存，不接管主滚动控制器。
        primary: false,
        padding: EdgeInsets.zero,
        itemCount: titles.length,
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return Material(
            color: selected ? AppColors.card : AppColors.fill,
            child: InkWell(
              onTap: () => onSelect(index),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        titles[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? AppColors.primary : AppColors.text2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 「展开 / 收起」开关（分组条目超过 3 行时出现）。
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Text(
              expanded ? '收起' : '展开',
              style: const TextStyle(fontSize: 12, color: AppColors.text3),
            ),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.text3,
            ),
          ],
        ),
      ),
    );
  }
}

/// 3 列等宽胶囊网格。
class _ChipGrid extends StatelessWidget {
  const _ChipGrid({required this.chips, required this.padding});

  final List<_Chip> chips;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 扣掉左右内边距与 2 个列间距（10×2）。
        final itemWidth = (constraints.maxWidth - padding.horizontal - 20) / 3;
        return Padding(
          padding: padding,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final chip in chips) _ChipBox(chip: chip, width: itemWidth),
            ],
          ),
        );
      },
    );
  }
}

/// 胶囊入口：点击进入对应分类 / 标签的作品列表。
class _ChipBox extends StatelessWidget {
  const _ChipBox({required this.chip, required this.width});

  final _Chip chip;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
          onTap: () => chip.open(context),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  chip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.text2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分组数据：一个标题 + 一组胶囊。
class _Group {
  const _Group({required this.label, required this.chips, this.collapsible = true});

  final String label;
  final List<_Chip> chips;

  /// 是否支持展开 / 收起。
  final bool collapsible;
}

/// 胶囊数据：标签走 tagId，分类走 categoryId，二者互斥。
class _Chip {
  const _Chip({required this.label, this.tagId, this.categoryId});

  final String label;
  final int? tagId;
  final int? categoryId;

  void open(BuildContext context) {
    context.push(
      RoutePath.workListUrl(tagId: tagId, categoryId: categoryId, title: label),
    );
  }
}
