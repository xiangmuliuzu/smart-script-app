# App 分类页三级分类 + 标签体系重写（Spec）

日期：2026-10-29
范围：`d:\code\smart-script-app`（Flutter App）
关联：后端 `smartscript-content` 三级分类迁移（子代理进行中）、PC 分类管理树形化（子代理进行中）

## 1. 目标

老师要求：App 底部导航「分类」参考小说平台做成**多级分类（3 级）**。用户进一步要求：

> 结合市面上的产品来设计一下，重写分类与标签这一整套逻辑，pc 端设计的分类与标签都要运用到 APP 中的这个页面

因此本页必须同时消费 **PC 分类管理维护的三级分类树** 与 **PC 标签管理维护的标签库**，版式参考番茄 / 起点 / 七猫，而不是当前的“三栏文字列表”或“左栏频道 + 右栏标签墙”。

### 已明确否决的版本（不得再复用）

1. 16 个题材当一级、左中右三栏纯文字列表 → 呆板。
2. 前端硬编码「男生频道 / 女生频道」分组 → 分类归属应由数据库 / PC 端维护。
3. 左栏窄频道 + 右侧题材分组标签墙 → 用户评价“太丑”。

## 2. 数据现状与依赖

云端开发库 `script_platform_dev`：

| 项 | 现状 | 迁移后（后端子代理负责） |
| --- | --- | --- |
| `sys_category` | 67 条：16 条 `parent_id=0` 题材 + 51 条细分（2 级） | 新增 2 个频道（146 男生 / 147 女生）→ 16 题材挂到频道下 → 51 细分挂题材下，共 69 条（3 级） |
| `sys_tag` | 32 条，字段 `tag_id/tag_name/tag_type/use_count/sort/status` | 不变 |

App 侧**不新增后端接口**，沿用已上线接口：

- `GET /content/categories?parentId=0`：取一级（迁移后为频道，迁移前为题材）
- `GET /content/categories?parentId={id}`：取下一级
- `GET /content/tags?categoryId={id}`：标签（按 `category_id` 过滤，可不传）
- `GET /content/works?categoryId=&tagId=&sort=&page=`：作品列表

> 说明：后端若新增 `/content/categories/tree`，本方案不依赖它，保持 App 可在当前后端直接跑通。

## 3. 页面设计（参考番茄 / 起点）

```
┌ AppBar  分类                                  [🔍]
├ 白底 sticky 头部（轻阴影）
│   ○ 男生频道    ● 女生频道        ← 一级：DB 频道，segmented pill 横滑
│   ────────────────────────────
│   [玄幻] [仙侠] [都市] [悬疑] …    ← 二级：当前频道的题材，chips 横滑，选中主色实心
├ 内容 ListView（pageBackground 灰底）
│   ┌ 渐变横幅卡片（主色 254E90 → 深蓝）
│   │  玄幻 · 全部作品                    查看全部 >
│   ├ 三级细分 2 列网格（卡片）
│   │  [东方玄幻]   [异世大陆]
│   │  [洪荒神话]   [更多…]
│   ├ 热门标签（白卡片，Wrap 圆角 chip）→ 点标签进 tagId 筛选列表
│   └ 为你推荐（白卡片，WorkListTile × ≤6）→ category_page 展示位推荐
└ 底部导航
```

### 视觉规范（沿用现有 design system）

- 主色 `AppColors.primary #254E90`、浅底 `primaryTint #EAF1FA`、页面底 `pageBackground #F6F8FA`、文字 `text1/2/3`、圆角 `AppRadius.r / rSmall`、`cardShadow`。
- 一级频道：未选中 `fill #F2F3F5` 底 + `text2`；选中主色实心 + 白字 + `StadiumBorder`。
- 二级题材 chips：未选中白底 `divider` 描边 + `text2`；选中 `primaryTint` 底 + `primary` 字 + `primary` 描边。
- 三级网格卡片：2 列、`childAspectRatio ≈ 1.9`、按索引取渐变（与 `WorkCover._palettes` 同一色板取前 4 组，保证与现有封面占位观感一致），左上分类名白色 `w600 14`，右下 `Icons.chevron_right` 白 70%。
- 热门标签 chip：`primaryTint` 底 + `primary` 字，圆角 14。
- 空态 / 加载 / 错误：沿用页面内轻量骨架 + 文本重试，不引入新组件。

### 交互

| 操作 | 结果 |
| --- | --- |
| 点一级频道 | 切频道，题材 chips 重新拉取，自动选中第一个题材 |
| 点题材 chip | 右栏切换该题材的三级细分（懒加载子分类） |
| 点「查看全部 >」 | `workListUrl(categoryId: 题材id, title: 题材名)` |
| 点三级卡片 | `workListUrl(categoryId: 细分id, title: 细分名)` |
| 点标签 chip | `workListUrl(tagId: tag.tagId, title: tag.tagName)` |
| 点推荐作品 | `workDetailUrl(workId)` |
| 下拉刷新 | 失效分类树、标签、推荐 |

## 4. 数据层改动（decision-complete）

### 4.1 `lib/features/bookstore/data/bookstore_models.dart`

新增（放在 `CategoryItem` 之后）：

```dart
/// 分类树节点（频道 → 题材两层；三级细分按需懒加载）。
class CategoryNode {
  const CategoryNode({required this.category, this.children = const <CategoryItem>[]});
  final CategoryItem category;
  final List<CategoryItem> children;
}
```

### 4.2 `lib/features/bookstore/data/content_repository.dart`

新增方法（`listCategories` 之后）：

```dart
/// 分类树（两级）：拉顶级后并行拉各自子级，供分类页与表单下拉共用。
Future<List<CategoryNode>> listCategoryTree() async {
  final top = await listCategories(parentId: 0);
  final children = await Future.wait(
    top.map((c) => listCategories(parentId: c.categoryId)),
  );
  return [
    for (var i = 0; i < top.length; i++)
      CategoryNode(category: top[i], children: children[i]),
  ];
}
```

### 4.3 `lib/features/bookstore/data/content_providers.dart`

- **删除** `categoriesProvider`（语义已变：顶级从题材变成频道，保留会误导）。
- **新增**：
  ```dart
  final categoryTreeProvider = FutureProvider.autoDispose<List<CategoryNode>>(
    (ref) => ref.watch(contentRepositoryProvider).listCategoryTree(),
  );

  /// 全部题材（二级）扁平表：树里有子级时取子级，否则回落顶级
  /// （兼容三级迁移尚未执行的环境）。供上传 / 设置 / 列表筛选下拉使用。
  final themeCategoriesProvider = FutureProvider.autoDispose<List<CategoryItem>>(
    (ref) async {
      final tree = await ref.watch(categoryTreeProvider.future);
      final themes = [for (final n in tree) ...n.children];
      return themes.isNotEmpty ? themes : [for (final n in tree) n.category];
    },
  );
  ```
- **保留** `childrenCategoriesProvider.family(parentId)`（三级细分懒加载）与 `tagsProvider.family<int?>`。

### 4.4 `lib/features/category/category_page.dart`（整体重写，约 420 行）

结构：

- `CategoryPage`（ConsumerWidget）：`Scaffold` + 透明底 + `AppBar('分类')` + 搜索 action（保持现状）。
- `_CategoryBrowser`（ConsumerStatefulWidget）：维护 `int? _channelId`、`int? _themeId`；watch `categoryTreeProvider`：
  - `channels = tree`；若 `tree.every((n) => n.children.isEmpty)`（迁移前兼容）则视为单层模式：频道行隐藏，题材 = `tree`，三级走 `childrenCategoriesProvider(题材id)`。
  - 选中的 channel 变化时（`didUpdateWidget`/首帧 post-frame）把 `_channelId` 归位到首个频道并把 `_themeId` 归位到该频道首个题材。
  - 布局：`Column[ _StickyHeader(频道 pills + 题材 chips), Expanded(RefreshIndicator(ListView[ 全部横幅, 三级网格, 热门标签, 为你推荐 ])) ]`。
- 私有组件（均在 `category_page.dart` 内）：
  - `_ChannelPill({selected, label, onTap})`
  - `_ThemeChip({selected, label, onTap})`
  - `_AllWorksBanner({theme})`：渐变卡，`onTap` → 列表页
  - `_SubGrid({theme})`：watch `childrenCategoriesProvider(theme.categoryId)`，2 列 `GridView.builder(shrinkWrap, physics: NeverScrollable, SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9))`；空 → 提示「该题材暂无细分」
  - `_SubTile({category, index})`：渐变圆角卡片
  - `_TagSection()`：watch `tagsProvider(null)`，`SectionHeader('热门标签')` + `Wrap` chip
  - `_RecommendSection()`：watch `categoryRecommendProvider`，`SectionHeader('为你推荐')` + `WorkListTile` 行

复用 `SectionHeader` / `WorkListTile` / `AppCard`（`bookstore_widgets.dart`）。

### 4.5 消费点替换（4 处）

| 文件 | 位置 | 改动 |
| --- | --- | --- |
| `lib/features/bookstore/bookstore_page.dart` | L71 `ref.invalidate(categoriesProvider)`；L302 `_CategoryEntries` | 改 `categoryTreeProvider`；分类胶囊取 `themeCategoriesProvider` 扁平题材（若为空回落到树顶级）；点击仍 `workListUrl(categoryId)` |
| `lib/features/bookstore/pages/work_list_page.dart` | L166 `ref.watch(categoriesProvider)` | 改 `ref.watch(themeCategoriesProvider)`，其余筛选逻辑与标题回显不变 |
| `lib/features/create/pages/work_upload_page.dart` | L102 watch、L109 error retry | 改 `themeCategoriesProvider`，下拉选项为题材（保持 `int` 值 = 题材 categoryId，与存量作品数据一致） |
| `lib/features/create/widgets/work_settings_tab.dart` | L259 watch | 改 `themeCategoriesProvider`，`_CategoryDropdown` 入参类型不变 |

> 上传 / 设置仍选**题材（二级）**，与现有作品 `genre_id` 数据兼容；三级细分只用于分类页浏览与列表筛选。

## 5. 验证

1. `cd d:\code\smart-script-app; flutter analyze lib` —— 0 error（允许既有测试 lint info）。
2. 数据库核验（迁移后）：`SELECT COUNT(*) FROM sys_category` = 69；频道 2 条 `parent_id=0`；每个题材有 `parent_id` 指向频道；每个细分 `parent_id` 指向题材。
3. 手工验证（模拟器，迁移后）：分类 tab → 频道可切、题材可切、三级卡片可点、标签可点、下拉刷新正常；迁移前环境不崩溃（单层兼容模式）。
4. `flutter test` 中 `test/features/bookstore` 相关用例（若有 provider 名称引用需同步）。

## 6. 风险与边界

- 后端迁移未执行时：App 走单层兼容模式，页面不空、不报错，但“频道”概念不出现。
- 后端若把作品列表 `categoryId` 改为子树聚合（子代理任务），点题材「查看全部」将包含其三级作品，符合预期；若未改，则只含精确匹配作品，页面仍可用。
- 不做：搜索页分类、分类浏览历史、分类页分页（沿用列表页）。

## 7. 需用户确认

1. 一级入口采用**数据库真实频道**（男生 / 女生），不再前端硬编码。若后续要“出版 / 短篇”等频道，在 PC 分类管理里加一级即可自动出现在 App。
2. 上传 / 设置下拉选**题材（二级）**而非三级细分，避免存量 40+ 作品分类失效。
3. 三级细分卡片用**渐变色块**（无真实分类封面图可用），不新增后台封面字段。
