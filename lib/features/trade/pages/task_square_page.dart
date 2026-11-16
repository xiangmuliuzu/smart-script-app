import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_providers.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import 'demand_list_page.dart';
import 'demand_my_tasks_page.dart';

/// 底部导航「任务」板块根页面（任务广场大板块）。
///
/// 结构：AppBar（标题）→ 分段 TabBar「广场 / 我的任务」→ 分段正文。
/// 两个分段各是独立组件，本页只做装配与跨分段刷新。
///
/// 游客可见：广场分段直接浏览（后端对游客返回字段白名单）；
/// 「我的任务」分段需要登录，未登录时只渲染登录引导占位，
/// 绝不发起 mine 请求——App 的 ApiClient 对任何 401 都按会话过期处理，
/// 游客误触发会被踢去登录页。
class TaskSquarePage extends ConsumerStatefulWidget {
  const TaskSquarePage({super.key});

  @override
  ConsumerState<TaskSquarePage> createState() => _TaskSquarePageState();
}

class _TaskSquarePageState extends ConsumerState<TaskSquarePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  final _squareKey = GlobalKey<DemandSquareSectionState>();
  final _myTasksKey = GlobalKey<DemandMyTasksSectionState>();

  static const int _myTasksTabIndex = 1;

  /// 游客取消登录后不再反复弹确认；分段内的登录引导入口常驻可点。
  bool _myTasksLoginPrompted = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  /// 分段切定后触发登录确认（与旧「我的任务」胶囊按钮同一条守卫路径）。
  void _onTabChanged() {
    // indexIsChanging=true 是切换动画进行中，只在落定那一次判定，避免重复弹窗
    if (!_tabCtrl.indexIsChanging || _tabCtrl.index != _myTasksTabIndex) return;
    if (_myTasksLoginPrompted) return;
    _myTasksLoginPrompted = true;
    AuthGuard.requireLogin(context, ref, target: RoutePath.demandTab);
  }

  @override
  Widget build(BuildContext context) {
    // watch 而非 read：登录态在页面停留期间恢复/变更时，分段内容要跟着重算
    final loggedIn = ref.watch(authControllerProvider).status ==
        AuthStatus.authenticated;

    return Scaffold(
      // 透明底透出 AppPageBackground 的全局冰蓝渐变，与首页/我的页同背景
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.text1,
        title: const Text(
          '任务广场',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2.5,
          labelColor: AppColors.text1,
          unselectedLabelColor: AppColors.text3,
          labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 15),
          tabs: const [
            Tab(text: '广场'),
            Tab(text: '我的任务'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          DemandSquareSection(key: _squareKey),
          loggedIn
              ? DemandMyTasksSection(key: _myTasksKey)
              : _buildLoginRequired(),
        ],
      ),
    );
  }

  Widget _buildLoginRequired() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 96),
        const EmptyView(
          message: '登录后即可查看我接取的任务',
          icon: Icons.lock_outline,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => AuthGuard.requireLogin(
              context,
              ref,
              target: RoutePath.demandTab,
            ),
            child: const Text('去登录'),
          ),
        ),
      ],
    );
  }
}
