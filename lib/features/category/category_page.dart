import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/common_views.dart';
import '../bookstore/data/bookstore_models.dart';
import '../bookstore/data/content_providers.dart';
import '../bookstore/widgets/bookstore_widgets.dart';

/// 分类（B 模块，接口文档 2.10：分类列表 / 标签列表）。
///
/// 公开页，游客可读。数据复用书城契约：GET /content/categories（顶级）
/// 与 GET /content/tags，二者均已存在，故本页不新增后端接口。
///
/// 点击分类 → 作品列表（?categoryId=）；点击标签 → 作品列表（?tagId=），
/// 列表页已支持这两个筛选参数，进入后由列表页自行分页。
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
      appBar: AppBar(title: const Text('分类')),
      body: !ready
          ? (error != null
              ? ErrorView(
                  message: error is ApiException ? error.message : '加载失败，请稍后重试',
                  onRetry: () => _refresh(ref),
                )
              : const LoadingView(message: '加载中'))
          : RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: _Content(
                categories: categoriesAsync.valueOrNull!,
                tags: tagsAsync.valueOrNull!,
              ),
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

class _Content extends StatelessWidget {
  const _Content({required this.categories, required this.tags});

  final List<CategoryItem> categories;
  final List<TagItem> tags;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty && tags.isEmpty) {
      return const CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(message: '暂无分类与标签', icon: Icons.category_outlined),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        if (categories.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: '剧本分类')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.4,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _CategoryTile(item: categories[index]),
                childCount: categories.length,
              ),
            ),
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: '热门标签')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags) _TagChip(item: tag),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 分类入口卡片：点击进入该分类的作品列表。
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.item});

  final CategoryItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.rSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        onTap: () => context.push(
          RoutePath.workListUrl(categoryId: item.categoryId, title: item.categoryName),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              item.categoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 标签入口胶囊：点击进入该标签的作品列表。
class _TagChip extends StatelessWidget {
  const _TagChip({required this.item});

  final TagItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(
        RoutePath.workListUrl(tagId: item.tagId, title: item.tagName),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          item.tagName,
          style: const TextStyle(fontSize: 12, color: AppColors.text2),
        ),
      ),
    );
  }
}