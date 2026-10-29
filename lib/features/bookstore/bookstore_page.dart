import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import 'data/bookstore_models.dart';
import 'data/content_providers.dart';
import 'widgets/bookstore_widgets.dart';

/// 书城首页（B 模块：内容与作品）。
///
/// 浏览链路全部为公开接口，游客可读；顶部「消息」是受保护入口，
/// 由 [AuthGuard.pushProtected] 统一拦截（未登录先登录，登录后回到消息页）。
class BookstorePage extends ConsumerWidget {
  const BookstorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 16,
        title: SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => context.push(RoutePath.search),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.fill,
              foregroundColor: AppColors.text3,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 14),
            ),
            icon: const Icon(Icons.search, size: 18),
            label: const Text(
              '搜索作品名称、作者、标签',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () => AuthGuard.pushProtected(
                context,
                ref,
                target: RoutePath.messages,
              ),
              icon: const Icon(Icons.notifications_none),
              tooltip: '消息',
            ),
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
          // 顶部不再留白：搜索栏已在透明 AppBar 内，渐变直接落到 Banner。
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const SizedBox(height: 16),
            const _BannerCarousel(position: 'home_top'),
            const AppCard(
              child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _RankingPreview(),
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WorkSection(title: '热门精选', provider: hotWorksProvider, showScope: 'bookstore'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页 Banner 轮播（顶部/中部共用）：多于一张时每 4 秒自动切换，可手动滑动。
/// [position] 决定取哪个展示位的 Banner，空位不占高度。
class _BannerCarousel extends ConsumerStatefulWidget {
  const _BannerCarousel({required this.position});

  final String position;

  @override
  ConsumerState<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<_BannerCarousel> {
  static const Duration _interval = Duration(seconds: 4);

  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;
  int _count = 0;

  /// 上一次渲染用的 Banner 列表实例：用于识别「数据是否刷新出了一份新数据」。
  /// Riverpod 每次成功取数都会生成新列表实例，未取数的重建保持同一实例。
  List<BannerItem> _lastBanners = const <BannerItem>[];

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
    final bannersAsync = ref.watch(bannersProvider(widget.position));

    // 首次加载（无历史数据）时渲染与轮播同高的灰底占位：否则数据到达瞬间 Banner
    // 才撑开 160，下方分类/榜单板块会整体上移跳动。下拉刷新时 isLoading 仍持有
    // 旧数据（hasValue=true），继续渲染旧 Banner，布局不跳动。
    if (bannersAsync.isLoading && !bannersAsync.hasValue) {
      return const _BannerSkeleton();
    }

    final banners = bannersAsync.valueOrNull ?? const <BannerItem>[];

    // 定时器只在数据就绪后启动，且不在 build 过程中直接创建。
    // 数据变化（数量变化或刷新出一份新数据）时下标归零并跳回首页：
    // 否则下拉刷新后 Banner 变少，PageView 停在越界旧下标，自动轮播基于旧计数
    // 还会跳到异常页。定时器本身的启停逻辑保持不变。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dataChanged = !identical(banners, _lastBanners);
      _lastBanners = banners;
      if (dataChanged && _index != 0 && _controller.hasClients) {
        setState(() => _index = 0);
        _controller.jumpToPage(0);
      }
      _syncAutoPlay(banners.length);
    });

    if (banners.isEmpty) {
      // 已加载但为空列表 / 首次加载失败：Banner 属装饰性内容，不占位，
      // 页面级下拉刷新可重试。
      return const SizedBox.shrink();
    }

    return Padding(
      // Banner 在首页区块里，由外层卡片提供左右留白；卡片内再加水平内边距会双重缩进。
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: SizedBox(
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
      ),
    );
  }
}

class _BannerImage extends StatelessWidget {
  const _BannerImage({required this.banner});

  final BannerItem banner;

  /// 点击跳转：仅 linkType=work 且有关联作品时跳作品详情，否则无动作。
  void _onTap(BuildContext context) {
    if (banner.linkType == 'work' && banner.linkId != null) {
      context.push(RoutePath.workDetailUrl(banner.linkId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (banner.imageUrl.isEmpty) return _placeholder();
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Image.network(
        AppConfig.resolveAssetUrl(banner.imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      ),
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

/// Banner 首次加载占位：与轮播同高（160）、同左右留白与圆角，灰底轻量骨架，
/// 避免数据到达瞬间 Banner 才撑开、下方板块整体上移跳动。
class _BannerSkeleton extends StatelessWidget {
  const _BannerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: SizedBox(
        height: 160,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.r),
            child: Container(color: AppColors.primaryTint),
          ),
        ),
      ),
    );
  }
}

/// 顶级分类入口（parent_id=0）。
class _CategoryEntries extends ConsumerWidget {
  const _CategoryEntries();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    return categoriesAsync.when(
      // loading 态暂保持不占位（骨架屏后续批次统一）。
      loading: () => const SizedBox.shrink(),
      // error 态必须可见：否则接口失败时用户以为书城根本没有分类。
      // 复用本文件 _SectionError，与榜单/作品区块的行内错误风格一致。
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: '分类'),
          _SectionError(
            message: error is ApiException ? error.message : '分类加载失败',
            onRetry: () => ref.invalidate(categoriesProvider),
          ),
        ],
      ),
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
                // 已在 AppCard 内，水平留白由卡片承担；两侧各留 2 使胶囊阴影不被裁剪。
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  // 原胶囊为 GestureDetector + 纯色 Container，点击无任何反馈；
                  // 改用 Material(承载底色) + InkWell 提供水波纹，圆角/底色/内边距/
                  // 文字与原胶囊完全一致，横向滑动布局与高度(34)不变。
                  return Material(
                    // 胶囊位于白色卡片内，用浅灰底区分，避免白底白字不可见。
                    color: AppColors.fill,
                    borderRadius: BorderRadius.circular(17),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: () => context.push(RoutePath.workListUrl(
                        categoryId: category.categoryId,
                        title: category.categoryName,
                      )),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          category.categoryName,
                          style: const TextStyle(fontSize: 13, color: AppColors.text2),
                        ),
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
  static const int _previewSize = 5;

  String _type = RankingType.all.first.code;

  @override
  Widget build(BuildContext context) {
    final rankingAsync = ref.watch(rankingProvider(_type));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '榜单'),
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
          data: (payload) {
            final items = payload.list;
            if (items.isEmpty) return const _SectionEmpty(message: '榜单暂无数据');
            final preview = items.take(_previewSize).toList();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  for (var i = 0; i < preview.length; i++)
                    RankingRow(
                      item: preview[i],
                      scoreText: _scoreText(preview[i]),
                      showDivider: i != preview.length - 1,
                      onTap: () => context.push(RoutePath.workDetailUrl(preview[i].workId)),
                    ),
                  // 底部"查看更多"按钮，明确表达"当前榜单还有更多内容"
                  TextButton(
                    onPressed: () => context.push(RoutePath.rankingUrl(_type)),
                    child: const Text('查看更多 >', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  String _scoreText(RankingItem item) {
    if (_type == 'rating') return '${item.score.toStringAsFixed(1)} 分';
    // 新书榜按上架时间排序，右侧展示上架日期而非阅读量
    if (_type == 'new') {
      return item.shelfTime.isNotEmpty
          ? item.shelfTime.substring(0, 10)
          : '—';
    }
    return '${item.score.toInt()}';
  }
}

/// 首页作品区块（热门 / 最新共用）：按 provider 取前若干部，完整列表进作品列表页。
class _WorkSection extends ConsumerWidget {
  const _WorkSection({required this.title, required this.provider, this.sort, this.showScope});

  final String title;
  final AutoDisposeFutureProvider<List<BookItem>> provider;

  /// 点「更多」带的初始排序值（与后端 normalizeSort 白名单一致，如 'view'）；
  /// 不传则列表页默认最新排序。热门区块传 'view'，最新区块不传。
  final String? sort;

  /// 点「更多」带的推荐展示位过滤（如 'bookstore'）；不传则列表页不过滤。
  final String? showScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          onMore: worksAsync.valueOrNull != null && worksAsync.value!.length > 6
              ? () => context.push(RoutePath.recommendList)
              : null,
        ),
        worksAsync.when(
          loading: () => const _SectionLoading(),
          error: (error, _) => _SectionError(
            message: error is ApiException ? error.message : '作品加载失败',
            onRetry: () => ref.invalidate(provider),
          ),
          data: (works) {
            if (works.isEmpty) return const _SectionEmpty(message: '暂无作品');
            // 首页区块只显示前 6 本，剩余的通过"更多"按钮进列表页看
            final displayWorks = works.take(6).toList();
            return Column(
              children: [
                for (var i = 0; i < displayWorks.length; i++)
                  WorkListTile(
                    work: displayWorks[i],
                    showDivider: i != displayWorks.length - 1,
                    onTap: () => context.push(RoutePath.workDetailUrl(displayWorks[i].workId)),
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
