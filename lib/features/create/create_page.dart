import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/auth_providers.dart';
import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/common_views.dart';
import '../bookstore/widgets/bookstore_widgets.dart';
import 'data/author_work_models.dart';
import 'data/author_work_providers.dart';

/// 创作入口（底部导航「创作」tab）。
///
/// 采用写作 App 书架范式：状态筛选 Tab + **三列网格**作品卡（封面 + 标题 + 分类 + 状态），
/// 三列使同屏作品数更多，封面保持近方形比例，作品多时上下滑动浏览。
/// 右上角「新建」进入创建表单；点卡片进入作品工作台（章节 / 设置 / 发布）。
///
/// 数据走 A 套 /users/me/works（写作链路），状态由服务端按最新审核记录派生。
class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key});

  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  /// 状态筛选项（value 与 A 套 status 入参一致；all 表示不过滤）。
  static const List<({String value, String label})> _filters = [
    (value: 'all', label: '全部'),
    (value: 'draft', label: '草稿'),
    (value: 'published', label: '已发布'),
    (value: 'reviewing', label: '审核中'),
    (value: 'revision', label: '待修改'),
    (value: 'rejected', label: '已驳回'),
  ];

  /// 网格列数（三列，同屏作品数更多）。
  static const int _columns = 3;

  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    // /create 根被有意排除在路由登录守卫外（避免拦截底部导航创作 tab），但本页数据来自
    // 需登录的 /users/me/works。此处做页面级兜底：未登录不监听列表 Provider、不发请求，
    // 页内引导登录；会话恢复中（unknown）按守卫契约视为可能已登录，先加载态等待，
    // 不误弹「登录已失效」。
    final auth = ref.watch(authControllerProvider);
    final authStatus = auth.status;
    final canCreate = auth.user?.authorCapability == true;
    final loggedIn = authStatus == AuthStatus.authenticated;
    // 未登录或未开通能力时不请求作者作品列表。
    final worksAsync = loggedIn && canCreate ? ref.watch(myWorksProvider(_status)) : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('我的作品'),
        actions: [
          // 新建入口仅对已开通创作能力的用户展示。
          if (loggedIn && canCreate)
            TextButton.icon(
              onPressed: () => context.push(RoutePath.workUpload),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('新建'),
            ),
        ],
      ),
      body: switch (authStatus) {
        // 会话恢复中：不请求、不引导，等 /auth/me 定论。
        AuthStatus.unknown => const LoadingView(message: '加载中'),
        // 游客：页内登录引导，不离开创作 tab；登录成功由 RouteIntent 回跳本页。
        AuthStatus.unauthenticated => _LoginPrompt(
            onLogin: () =>
                AuthGuard.requireLogin(context, ref, target: RoutePath.create),
          ),
        // 未开通或被关闭能力：阻断创作并引导申请。
        AuthStatus.authenticated when !canCreate => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('请先申请开通创作者能力'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.push(RoutePath.creatorApply),
                  child: const Text('去申请'),
                ),
              ],
            ),
          ),
        AuthStatus.authenticated => Column(
            children: [
              _FilterBar(
                filters: _filters,
                selected: _status,
                onChanged: (value) => setState(() => _status = value),
              ),
              Expanded(
                child: worksAsync!.when(
                  loading: () => const LoadingView(message: '加载中'),
                  error: (error, _) => ErrorView(
                    message: error is ApiException ? error.message : '加载失败，请稍后重试',
                    onRetry: () => ref.invalidate(myWorksProvider(_status)),
                  ),
                  data: _buildGrid,
                ),
              ),
            ],
          ),
      },
    );
  }

  Widget _buildGrid(List<AuthorWorkItem> works) {
    if (works.isEmpty) {
      return const _EmptyWorks();
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myWorksProvider(_status)),
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 10,
          // 竖向卡片：封面占大头，下方留出标题行 + 「分类 + 状态」行。
          childAspectRatio: 0.65,
        ),
        itemCount: works.length,
        itemBuilder: (context, index) {
          final work = works[index];
          return _WorkCard(
            work: work,
            onTap: () => context.push(
              RoutePath.workWorkspaceUrl(
                workId: work.workId,
                title: work.title,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 状态筛选条（横向可滚动标签）。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onChanged,
  });

  final List<({String value, String label})> filters;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filter.label),
                  selected: selected == filter.value,
                  onSelected: (_) => onChanged(filter.value),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: selected == filter.value
                        ? AppColors.primary
                        : AppColors.text2,
                  ),
                  selectedColor: AppColors.primaryTint,
                  backgroundColor: AppColors.card,
                  side: BorderSide(
                    color: selected == filter.value
                        ? AppColors.primary
                        : AppColors.divider,
                  ),
                  showCheckmark: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 封面下方文字区预留高度（标题行 + 「分类 + 状态」行 + 内边距）。
const double _kCardTextHeight = 56;

/// 网格作品卡：封面上，标题与「分类 + 状态角标」在下。
class _WorkCard extends StatelessWidget {
  const _WorkCard({
    required this.work,
    required this.onTap,
  });

  final AuthorWorkItem work;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = work.title.isEmpty ? '未命名作品' : work.title;
    final genre = (work.genreName != null && work.genreName!.isNotEmpty)
        ? work.genreName!
        : '未分类';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.r),
          boxShadow: AppColors.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 卡片高度固定，封面吃掉文字区之外的全部高度，不写死尺寸也不溢出。
              final coverHeight = (constraints.maxHeight - _kCardTextHeight)
                  .clamp(48.0, constraints.maxHeight);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面铺满卡片宽度，圆角交给外层 ClipRRect，避免出现双层圆角。
                  WorkCover(
                    url: work.cover ?? '',
                    title: title,
                    width: constraints.maxWidth,
                    height: coverHeight,
                    radius: 0,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 三列卡片宽度有限，状态角标与分类同行，避免标题被挤到只剩两三个字。
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                genre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppColors.text3),
                              ),
                            ),
                            const SizedBox(width: 4),
                            _StatusBadge(status: work.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 状态角标（审核派生状态）：不同状态用语义色区分，便于一眼掌握作品进度。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'published' => AppColors.success,
      'reviewing' => AppColors.warning,
      'revision' => AppColors.warning,
      'rejected' => AppColors.danger,
      _ => AppColors.text3,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          workStatusLabel(status),
          style: TextStyle(fontSize: 10, color: color),
        ),
      ),
    );
  }
}

/// 空态：尚无作品时引导新建。
///
/// 新建主入口统一保留在 AppBar「新建」（空态 / 有作品态一致，有作品时唯一入口就在
/// AppBar）；此处不再重复放置右下角 FAB，避免同一页面出现两个新建入口。
class _EmptyWorks extends StatelessWidget {
  const _EmptyWorks();

  @override
  Widget build(BuildContext context) {
    return const EmptyView(
      message: '还没有作品，点击右上角「新建」开始创作',
      icon: Icons.menu_book_outlined,
    );
  }
}

/// 游客态页内登录引导。
///
/// /create 根被有意排除在路由登录守卫外（见 [ProtectedRoutes] 注释），以保留底部导航
/// 创作 tab 可进入；但本页数据来自需登录的 /users/me/works，故游客不再直接发请求，
/// 而是在此引导登录。点击走统一守卫 [AuthGuard.requireLogin]，回跳意图指向本页，
/// 登录成功后由 resolvePostLoginTarget 以 go 切回创作分支并刷新列表。
class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_outline, size: 56, color: AppColors.text3),
          const SizedBox(height: 12),
          const Text('登录后查看我的作品', style: TextStyle(color: AppColors.text3)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onLogin,
            child: const Text('去登录'),
          ),
        ],
      ),
    );
  }
}
