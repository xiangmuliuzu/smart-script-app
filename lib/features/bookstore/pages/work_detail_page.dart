import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';
import '../widgets/bookstore_widgets.dart';

/// 作品详情（B 模块，接口 2.7.2 作品详情）。
///
/// 公开页，游客可读。未上架或已删除的作品后端按 404 拒绝，此处落到错误态。
class WorkDetailPage extends ConsumerWidget {
  const WorkDetailPage({super.key, required this.workId});

  final int workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(workDetailProvider(workId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('作品详情'),
        actions: [_ShelfButton(workId: workId), _FavoriteButton(workId: workId)],
      ),
      body: detailAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(workDetailProvider(workId)),
        ),
        data: (work) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(workDetailProvider(workId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),  // 留出底部栏空间，卡片左右留白
            children: [
              _Header(work: work),
              _RatingBar(workId: work.workId),
              _ChapterEntry(work: work),
              _ContactEntry(workId: work.workId),
              if (work.summary.isNotEmpty)
                _Block(title: '作品简介', content: work.summary),
              if (work.coreSetting.isNotEmpty)
                _Block(title: '核心设置', content: work.coreSetting),
              if (work.characterSetting.isNotEmpty)
                _Block(title: '角色设定', content: work.characterSetting),
              _InfoBlock(work: work),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _TradeBottomBar(workId: workId),
    );
  }
}

/// 读者打分模块：极简细条（不独占整卡）。
///
/// 读者打过分后几乎不再操作，故从独立大卡压缩为头部下方一条浅底细条：
/// 仅保留「我的评分 + 小星星」打分入口；平均分由头部数据栏「评分」格展示，
/// 不再重复、不抢眼。游客点击星星先经 [AuthGuard.pushProtected] 引导登录。
class _RatingBar extends ConsumerStatefulWidget {
  const _RatingBar({required this.workId});

  final int workId;

  @override
  ConsumerState<_RatingBar> createState() => _RatingBarState();
}

class _RatingBarState extends ConsumerState<_RatingBar> {
  /// 星级上限（每星 2 分、满分 10 分，与后端 2~10 口径一致）。
  static const int _maxScore = 5;

  bool _busy = false;

  Future<void> _rate(BuildContext context, int score) async {
    if (!AuthGuard.isLoggedIn(ref)) {
      // 登录成功后回到本作品详情（RouteIntent 会还原整串）。
      AuthGuard.pushProtected(
        context,
        ref,
        target: RoutePath.workDetailUrl(widget.workId),
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(contentRepositoryProvider).submitRating(widget.workId, score);
      // 打分态与作品平均分一并失效：详情页数据栏「评分」与书城列表随之刷新
      ref.invalidate(workRatingProvider(widget.workId));
      ref.invalidate(workDetailProvider(widget.workId));
      // 低危一致性修复：评分会改动作品平均分，首页「热门作品」与各榜单预览可能仍是旧值。
      // 仅做失效（invalidate）让其下次 watch 时重新拉取，不改数据流：
      // - hotWorksProvider 是普通 autoDispose FutureProvider，直接失效；
      // - rankingProvider 是 <String, …> family（type: view/favorite/sale/rating），
      //   首页预览默认停在某一档、用户可切 chip，故按 RankingType.all 逐档失效，
      //   覆盖当前正在展示的那档，避免漏刷。
      ref.invalidate(hotWorksProvider);
      for (final type in RankingType.all) {
        ref.invalidate(rankingProvider(type.code));
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('评分成功：$score 分')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthGuard.isLoggedIn(ref);
    final rating =
        loggedIn ? ref.watch(workRatingProvider(widget.workId)).valueOrNull : null;
    final int myScore = rating?.myScore ?? 0;
    final String hint = !loggedIn
        ? '登录后可评分'
        : (rating?.myScore == null ? '点击星星评分' : '已评 $myScore 分，可修改');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Row(
        children: [
          const Text('我的评分', style: TextStyle(fontSize: 12, color: AppColors.text3)),
          const SizedBox(width: 8),
          for (int star = 1; star <= _maxScore; star++)
            GestureDetector(
              // 每星 2 分：第 N 颗星提交 N*2 分（2/4/6/8/10）
              onTap: _busy ? null : () => _rate(context, star * 2),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Icon(
                  star * 2 <= myScore ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 18,
                  color: star * 2 <= myScore ? AppColors.warning : AppColors.text3,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 加入/移出书架按钮（接口 2.7.12）。
///
/// 与收藏按钮同为公开页上的登录态动作：游客点击时先经 [AuthGuard.pushProtected]
/// 引导登录并回跳，不为必然 401 的请求往返；登录态下按服务端下发的书架态切换。
class _ShelfButton extends ConsumerStatefulWidget {
  const _ShelfButton({required this.workId});

  final int workId;

  @override
  ConsumerState<_ShelfButton> createState() => _ShelfButtonState();
}

class _ShelfButtonState extends ConsumerState<_ShelfButton> {
  bool _busy = false;

  Future<void> _toggle(BuildContext context) async {
    if (!AuthGuard.isLoggedIn(ref)) {
      AuthGuard.pushProtected(
        context,
        ref,
        target: RoutePath.workDetailUrl(widget.workId),
      );
      return;
    }
    if (_busy) return;
    // 双保险：接口未返回有效值（加载中/失败）时不做任何反向操作，
    // 避免把未知态误判为「未加入」而重复加入并弹出与事实相反的提示。
    final onShelf =
        ref.read(shelfStatusProvider(widget.workId)).valueOrNull?.onShelf;
    if (onShelf == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(contentRepositoryProvider);
      if (onShelf) {
        await repo.removeShelf(widget.workId);
      } else {
        await repo.addShelf(widget.workId);
      }
      ref.invalidate(shelfStatusProvider(widget.workId));
      // 书架页与个人中心书架预览同步失效，避免回显过期列表。
      ref.invalidate(shelfProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(onShelf ? '已移出书架' : '已加入书架')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthGuard.isLoggedIn(ref);
    final shelfStatus =
        loggedIn ? ref.watch(shelfStatusProvider(widget.workId)) : null;
    final onShelf = shelfStatus?.valueOrNull?.onShelf ?? false;
    // 登录态下接口尚未返回有效值（加载中/失败）时禁用按钮，未知态不可操作；
    // 游客保持可点，点击走登录引导。
    final enabled = loggedIn ? shelfStatus?.valueOrNull != null : true;
    return IconButton(
      onPressed: (_busy || !enabled) ? null : () => _toggle(context),
      icon: Icon(onShelf ? Icons.bookmark : Icons.bookmark_add_outlined),
      tooltip: onShelf ? '移出书架' : '加入书架',
    );
  }
}

/// 收藏按钮（接口 2.7.10）。
///
/// 详情页是公开页：游客点击时先经 [AuthGuard.pushProtected] 引导登录并回跳，
/// 不为必然 401 的请求往返；登录态下按服务端下发的收藏态切换。
class _FavoriteButton extends ConsumerStatefulWidget {
  const _FavoriteButton({required this.workId});

  final int workId;

  @override
  ConsumerState<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<_FavoriteButton> {
  bool _busy = false;

  Future<void> _toggle(BuildContext context) async {
    if (!AuthGuard.isLoggedIn(ref)) {
      // 登录成功后回到本作品详情（RouteIntent 会还原整串）。
      AuthGuard.pushProtected(
        context,
        ref,
        target: RoutePath.workDetailUrl(widget.workId),
      );
      return;
    }
    if (_busy) return;
    // 双保险：接口未返回有效值（加载中/失败）时不做任何反向操作，
    // 避免把未知态误判为「未收藏」而重复收藏并弹出与事实相反的提示。
    final favorited =
        ref.read(favoriteStatusProvider(widget.workId)).valueOrNull?.favorited;
    if (favorited == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(contentRepositoryProvider);
      if (favorited) {
        await repo.removeFavorite(widget.workId);
      } else {
        await repo.addFavorite(widget.workId);
      }
      ref.invalidate(favoriteStatusProvider(widget.workId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(favorited ? '已取消收藏' : '已收藏')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthGuard.isLoggedIn(ref);
    final favoriteStatus =
        loggedIn ? ref.watch(favoriteStatusProvider(widget.workId)) : null;
    final favorited = favoriteStatus?.valueOrNull?.favorited ?? false;
    // 登录态下接口尚未返回有效值（加载中/失败）时禁用按钮，未知态不可操作；
    // 游客保持可点，点击走登录引导。
    final enabled = loggedIn ? favoriteStatus?.valueOrNull != null : true;
    return IconButton(
      onPressed: (_busy || !enabled) ? null : () => _toggle(context),
      icon: Icon(
        favorited ? Icons.star : Icons.star_border,
        color: favorited ? AppColors.warning : null,
      ),
      tooltip: favorited ? '取消收藏' : '收藏',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.work});

  final BookItem work;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面 + 浅蓝衬底（番茄/七猫式封面强调，突出作品主体）
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.r + 4),
                ),
                child: WorkCover(
                  url: work.cover,
                  width: 96,
                  height: 132,
                  radius: AppRadius.rSmall,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 作品名：加大加粗，作为头部唯一主视觉（作者名已降级到信息区）
                    Text(
                      work.title.isEmpty ? '未命名作品' : work.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text1,
                        height: 1.25,
                      ),
                    ),
                    if (work.genreName.isNotEmpty || work.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      WorkTagChips(
                        genreName: work.genreName,
                        tags: work.tags,
                        onGenreTap: work.genreId > 0
                            ? () => context.push(RoutePath.workListUrl(
                                  categoryId: work.genreId,
                                  title: work.genreName,
                                ))
                            : null,
                        onTagTap: (tag) => context.push(RoutePath.workListUrl(
                              tagId: tag.tagId,
                              title: tag.tagName,
                            )),
                      ),
                    ],
                    // 价格紧邻标签自然排布，卡片行高由封面主导
                    const SizedBox(height: 14),
                    Text(
                      work.priceLabel,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: work.isFree ? AppColors.success : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(label: '浏览', value: _compactCount(work.viewCount)),
              const SizedBox(width: 8),
              _Stat(label: '收藏', value: _compactCount(work.favoriteCount)),
              const SizedBox(width: 8),
              _Stat(label: '销量', value: _compactCount(work.saleCount)),
              const SizedBox(width: 8),
              _Stat(
                label: '评分',
                value: work.rating.toStringAsFixed(1),
                icon: Icons.star_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 章节目录入口（B 模块试读链路）。
class _ChapterEntry extends StatelessWidget {
  const _ChapterEntry({required this.work});

  final BookItem work;

  @override
  Widget build(BuildContext context) {
    // 试读状态合并判定：平台试读范围（当前无写入方，恒为未开）+ 作者逐章标记的免费章节
    final String subtitle = work.previewEnabled && work.previewEpisodes > 0
        ? '可试读前 ${work.previewEpisodes} 集'
        : (work.freeChapterCount > 0
            ? '${work.freeChapterCount} 章可免费阅读'
            : '暂未开启试读');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: () => context.push(
          RoutePath.chapterListUrl(work.workId, title: work.title),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.menu_book_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                '章节目录',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// C 交易域底部固定栏（发起询盘 / 我的询盘）。
///
/// 固定在页面底部，始终可见。未开启交易的作品点击时给提示。
class _TradeBottomBar extends ConsumerWidget {
  const _TradeBottomBar({required this.workId});

  final int workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(workDetailProvider(workId)).valueOrNull;
    final tradeEnabled = work?.tradeEnabled ?? false;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          // 发起询盘：主按钮（实心主色、更高更宽），页面主 CTA
          Expanded(
            flex: 3,
            child: _TradeButton(
              icon: Icons.send_outlined,
              label: '发起询盘',
              enabled: tradeEnabled,
              primary: true,
              onTap: () => _onInquiryTap(context, ref, work),
            ),
          ),
          const SizedBox(width: 12),
          // 我的询盘：次要按钮（浅底描边）
          Expanded(
            flex: 2,
            child: _TradeButton(
              icon: Icons.list_alt_outlined,
              label: '我的询盘',
              enabled: true,
              onTap: () => _onListTap(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  void _onInquiryTap(BuildContext context, WidgetRef ref, BookItem? work) {
    if (work == null || !work.tradeEnabled) {
      showAppToast(context, '该作品尚未开启交易，暂不能发起询盘');
      return;
    }
    if (!AuthGuard.isLoggedIn(ref)) {
      AuthGuard.pushProtected(
        context,
        ref,
        target: '${RoutePath.inquiryCreate}?workId=${work.workId}&title=${Uri.encodeComponent(work.title)}',
      );
      return;
    }
    context.push(
      '${RoutePath.inquiryCreate}?workId=${work.workId}&title=${Uri.encodeComponent(work.title)}',
    );
  }

  void _onListTap(BuildContext context, WidgetRef ref) {
    if (!AuthGuard.isLoggedIn(ref)) {
      AuthGuard.pushProtected(context, ref, target: RoutePath.inquiryList);
      return;
    }
    context.push(RoutePath.inquiryList);
  }
}

/// 交易域操作按钮。
///
/// [primary] 为 true 时作为主按钮（实心主色、加粗加高）；否则为次要按钮
/// （浅底描边），用于「我的询盘」这类次级操作，形成视觉主次。
class _TradeButton extends StatelessWidget {
  const _TradeButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;
    final Color? borderColor;
    if (!enabled) {
      bgColor = Colors.grey.shade300;
      textColor = Colors.grey.shade600;
      borderColor = null;
    } else if (primary) {
      bgColor = AppColors.primary;
      textColor = Colors.white;
      borderColor = null;
    } else {
      bgColor = AppColors.primaryTint;
      textColor = AppColors.primary;
      borderColor = AppColors.primary;
    }
    final suffix = enabled ? '' : '（未开启）';

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: primary ? 14 : 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 6),
              Text(
                '$label$suffix',
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                  fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 版权合作联系方式。
///
/// 展示作者登记的手机号/邮箱/微信号；未登记时显示提示文案。
class _ContactEntry extends ConsumerWidget {
  const _ContactEntry({required this.workId});

  final int workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactAsync = ref.watch(workContactProvider(workId));
    final contact = contactAsync.valueOrNull;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              const Icon(Icons.contact_mail_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                '作者联系方式',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 联系方式内容
          if (contact == null)
            Text(
              contactAsync.hasError ? '联系方式加载失败' : '加载中...',
              style: const TextStyle(fontSize: 13, color: AppColors.text3),
            )
          else if (!contact.hasContact)
            const Text(
              '作者暂未登记联系方式',
              style: TextStyle(fontSize: 13, color: AppColors.text3),
            )
          else
            _buildContactItems(contact),
        ],
      ),
    );
  }

  Widget _buildContactItems(WorkContact contact) {
    final items = <Widget>[];
    if (contact.phone.isNotEmpty) {
      items.add(_contactRow(Icons.phone, '手机号', contact.phone));
    }
    if (contact.email.isNotEmpty) {
      items.add(_contactRow(Icons.email, '邮箱', contact.email));
    }
    if (contact.wechat.isNotEmpty) {
      items.add(_contactRow(Icons.chat_bubble_outline, '微信号', contact.wechat));
    }
    if (items.isEmpty) {
      return const Text(
        '作者已登记联系方式，但当前不可见',
        style: TextStyle(fontSize: 13, color: AppColors.text3),
      );
    }
    return Column(children: items);
  }

  Widget _contactRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            '$label：',
            style: const TextStyle(fontSize: 13, color: AppColors.text3),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: AppColors.text1),
            ),
          ),
        ],
      ),
    );
  }
}

/// 数据栏大数字压缩：≥1 万折算为「x.xw」（整数不带小数，如 1w；
/// 1234567 → 123.5w），与番茄/七猫式数据栏口径一致，避免长数字撑破等宽格子。
String _compactCount(int n) {
  if (n < 10000) return '$n';
  final w = n / 10000.0;
  final text = w == w.roundToDouble()
      ? w.toStringAsFixed(0)
      : w.toStringAsFixed(1);
  return '${text}w';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.icon});

  final String label;
  final String value;

  /// 数值前的语义图标（如评分格的金色星标）；为空则不显示。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color valueColor = icon != null ? AppColors.warning : AppColors.text1;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
        ),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: valueColor),
                  const SizedBox(width: 2),
                ],
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.text3)),
          ],
        ),
      ),
    );
  }
}

/// 长文本区块（简介 / 核心设置 / 角色设定）。
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.text2),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.work});

  final BookItem work;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '作品信息',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 12),
          // 作者名从头部降级至此，作为作品信息第一项
          _InfoRow(label: '作者', value: work.authorName),
          _InfoRow(label: '字数', value: '${work.wordCount}'),
          _InfoRow(label: '集数', value: '${work.episodeCount}'),
          // duration 后端默认 0（未填时长）：0 分钟是无意义占位，按信息区既有「空值 → —」
          // 惯例（见 _InfoRow 的 value.isEmpty ? '—'）置空，不显示「0 分钟」。
          _InfoRow(label: '时长', value: work.duration > 0 ? '${work.duration} 分钟' : ''),
          _InfoRow(label: '是否开启交易', value: work.tradeEnabled ? '是' : '否'),
          _InfoRow(
            label: '试读',
            value: work.previewEnabled
                ? '已开启，共 ${work.previewEpisodes} 集'
                : (work.freeChapterCount > 0
                    ? '已开启，共 ${work.freeChapterCount} 章可免费阅读'
                    : '未开启'),
          ),
          _InfoRow(label: '上架时间', value: work.createTime ?? '—'),
          const Divider(height: 18, thickness: 0.5, color: AppColors.divider),
          // 作品类型/上传类型/篇幅类型/质量等级等后台字段收进「更多信息」折叠
          _MoreInfo(work: work),
        ],
      ),
    );
  }
}

/// 「标签 - 值」信息行（信息区通用）。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 13, color: AppColors.text1),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「更多信息」折叠区：后台技术字段（类型/上传/篇幅/质量等级）默认收起，
/// 点击展开，避免像后台表格一样铺满读者页面。
class _MoreInfo extends StatefulWidget {
  const _MoreInfo({required this.work});

  final BookItem work;

  @override
  State<_MoreInfo> createState() => _MoreInfoState();
}

class _MoreInfoState extends State<_MoreInfo> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Text(
                  '更多信息',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.text3),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          _InfoRow(label: '作品类型', value: work.workType),
          _InfoRow(label: '上传类型', value: work.uploadType),
          _InfoRow(label: '篇幅类型', value: work.lengthType),
          _InfoRow(label: '质量等级', value: work.qualityLevel),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}