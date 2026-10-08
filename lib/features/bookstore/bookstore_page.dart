import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import 'data/bookstore_models.dart';
import 'data/content_providers.dart';
import 'widgets/bookstore_widgets.dart';

/// 书城首页（B 模块：内容与作品）。
///
/// 浏览链路全部为公开接口，游客可读；只有「我的书架」是受保护入口，
/// 由 [AuthGuard.pushProtected] 统一拦截（未登录先登录，登录后回到书架）。
class BookstorePage extends ConsumerWidget {
  const BookstorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('书城'),
        actions: [
          IconButton(
            onPressed: () => context.push(RoutePath.search),
            icon: const Icon(Icons.search),
            tooltip: '搜索',
          ),
          TextButton.icon(
            onPressed: () => AuthGuard.pushProtected(
              context,
              ref,
              target: RoutePath.bookshelf,
            ),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('我的书架'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(bannersProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(hotWorksProvider);
          ref.invalidate(latestWorksProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const SizedBox(height: 12),
            const _BannerCarousel(),
            const _CategoryEntries(),
            const _RankingPreview(),
            _WorkSection(title: '热门作品', provider: hotWorksProvider),
            _WorkSection(title: '最新作品', provider: latestWorksProvider),
          ],
        ),
      ),
    );
  }
}

/// 首页 Banner 轮播：多于一张时每 4 秒自动切换，可手动滑动。
class _BannerCarousel extends ConsumerStatefulWidget {
  const _BannerCarousel();

  @override
  ConsumerState<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<_BannerCarousel> {
  static const Duration _interval = Duration(seconds: 4);

  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;
  int _count = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 按当前数量同步定时器；数据变化时重建，少于两张不轮播。
  void _syncAutoPlay(int count) {
    if (count == _count) return;
    _count = count;
    _timer?.cancel();
    if (count < 2) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % count,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(bannersProvider);
    final banners = bannersAsync.valueOrNull ?? const <BannerItem>[];

    // 定时器只在数据就绪后启动，且不在 build 过程中直接创建。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAutoPlay(banners.length);
    });

    if (banners.isEmpty) {
      // Banner 属于装饰性内容：加载中或失败时不占位，页面级下拉刷新可重试。
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 160,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: banners.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.r),
                child: _BannerImage(banner: banners[index]),
              ),
            ),
          ),
          if (banners.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < banners.length; i++)
                    Container(
                      width: i == _index ? 14 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.card : AppColors.card.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BannerImage extends StatelessWidget {
  const _BannerImage({required this.banner});

  final BannerItem banner;

  @override
  Widget build(BuildContext context) {
    if (banner.imageUrl.isEmpty) return _placeholder();
    return Image.network(
      banner.imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.primaryTint,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, color: AppColors.primary, size: 28),
            if (banner.title.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                banner.title,
                style: const TextStyle(fontSize: 13, color: AppColors.primary),
              ),
            ],
          ],
        ),
      );
}

/// 顶级分类入口（parent_id=0）。
class _CategoryEntries extends ConsumerWidget {
  const _CategoryEntries();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    return categoriesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (categories) {
        if (categories.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: '分类'),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return GestureDetector(
                    onTap: () => context.push(RoutePath.workListUrl(
                      categoryId: category.categoryId,
                      title: category.categoryName,
                    )),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        category.categoryName,
                        style: const TextStyle(fontSize: 13, color: AppColors.text2),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 榜单预览：切换榜单类型只看前三，完整榜单进榜单页。
class _RankingPreview extends ConsumerStatefulWidget {
  const _RankingPreview();

  @override
  ConsumerState<_RankingPreview> createState() => _RankingPreviewState();
}

class _RankingPreviewState extends ConsumerState<_RankingPreview> {
  static const int _previewSize = 3;

  String _type = RankingType.all.first.code;

  @override
  Widget build(BuildContext context) {
    final rankingAsync = ref.watch(rankingProvider(_type));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '榜单',
          onMore: () => context.push(RoutePath.rankingUrl(_type)),
        ),
        FilterChipBar(
          items: [
            for (final type in RankingType.all)
              FilterChipItem(
                label: type.label,
                selected: type.code == _type,
                onTap: () => setState(() => _type = type.code),
              ),
          ],
        ),
        rankingAsync.when(
          loading: () => const _SectionLoading(),
          error: (error, _) => _SectionError(
            message: error is ApiException ? error.message : '榜单加载失败',
            onRetry: () => ref.invalidate(rankingProvider(_type)),
          ),
          data: (items) {
            if (items.isEmpty) return const _SectionEmpty(message: '榜单暂无数据');
            return Container(
              color: AppColors.card,
              child: Column(
                children: [
                  for (final item in items.take(_previewSize))
                    RankingRow(
                      item: item,
                      scoreText: _scoreText(item),
                      onTap: () => context.push(RoutePath.workDetailUrl(item.workId)),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  String _scoreText(RankingItem item) =>
      _type == 'rating' ? '${item.score.toStringAsFixed(1)} 分' : '${item.score.toInt()}';
}

/// 首页作品区块（热门 / 最新共用）：按 provider 取前若干部，完整列表进作品列表页。
class _WorkSection extends ConsumerWidget {
  const _WorkSection({required this.title, required this.provider});

  final String title;
  final AutoDisposeFutureProvider<List<BookItem>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          onMore: () => context.push(RoutePath.workListUrl()),
        ),
        worksAsync.when(
          loading: () => const _SectionLoading(),
          error: (error, _) => _SectionError(
            message: error is ApiException ? error.message : '作品加载失败',
            onRetry: () => ref.invalidate(provider),
          ),
          data: (works) {
            if (works.isEmpty) return const _SectionEmpty(message: '暂无作品');
            return Column(
              children: [
                for (final work in works)
                  WorkListTile(
                    work: work,
                    onTap: () => context.push(RoutePath.workDetailUrl(work.workId)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(message, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
            TextButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      );
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
        ),
      );
}