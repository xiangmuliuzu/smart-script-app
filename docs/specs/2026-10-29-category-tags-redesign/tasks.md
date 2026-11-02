# App 分类页三级分类 + 标签重写 · 任务清单

对应 spec：`docs/specs/2026-10-29-category-tags-redesign/spec.md`

## T1 数据模型
- [x] `lib/features/bookstore/data/bookstore_models.dart` 新增 `CategoryNode{category, children}`
- 验收：`flutter analyze` 无 error

## T2 仓库层
- [x] `lib/features/bookstore/data/content_repository.dart` 新增 `listCategoryTree()`（顶级 + `Future.wait` 并行子级）
- 验收：analyze 通过

## T3 Provider
- [x] `content_providers.dart` 删除 `categoriesProvider`，新增 `categoryTreeProvider`、`themeCategoriesProvider`
- [x] 保留 `childrenCategoriesProvider`、`tagsProvider`
- 验收：analyze 通过

## T4 分类页重写
- [x] 重写 `lib/features/category/category_page.dart`：
  - 频道 pill 行（数据驱动，去掉前端硬编码）
  - 题材 chips 行
  - 「全部作品」渐变横幅
  - 三级细分 2 列渐变网格（`childrenCategoriesProvider` 懒加载）
  - 热门标签区块（`tagsProvider(null)`）
  - 为你推荐（`categoryRecommendProvider`）
  - 下拉刷新 + loading/error/empty
  - 迁移前单层兼容（顶级无子级时视为题材）
- 验收：analyze 通过

## T5 消费点替换
- [x] `bookstore_page.dart`：`_CategoryEntries` 与 refresh 改用新 provider
- [x] `work_list_page.dart`：L166 改 `themeCategoriesProvider`
- [x] `work_upload_page.dart`：L102/L109 改 `themeCategoriesProvider`
- [x] `work_settings_tab.dart`：L259 改 `themeCategoriesProvider`
- 验收：analyze 无 error

## T6 全量验证
- [x] `flutter analyze lib`：0 error（89 条均为既有 info）
- [x] `flutter test test/bookstore`：3 通过
- [x] 数据库核验：`sys_category` = 69 条；顶级 = 男生频道(146) / 女生频道(147)；男生 12 题材/39 细分，女生 4 题材/12 细分
- [x] 后端测试：`mvn -pl smartscript-content test` 184 项 0 失败；迁移脚本幂等 PASS
- [x] PC 分类管理：`npm run build` / lint / typecheck / test 全通过
- [x] 真机（模拟器）验证：频道切换、题材切换、三级卡片跳转、标签、最新上架回落、下拉刷新均正常

## T7 交付
- [ ] 汇总改动给用户，确认后提交推送三仓库
