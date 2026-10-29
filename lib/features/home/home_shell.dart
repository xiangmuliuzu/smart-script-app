import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';
import '../../core/providers/auth_providers.dart';
import '../../core/theme/app_colors.dart';

/// 主框架的底部导航容器（对应 UI 原型 `.tabbar` 五格平铺 + 中间圆形凸起）。
///
/// 四个 tab 分支（书城 / 视频 / 分类 / 我的）由 [StatefulNavigationShell] 管理，
/// 切 tab 会保留各自导航栈；中间「创作」是新建作品的快捷入口，不占用分支。
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = <_TabItem>[
    _TabItem('首页', Icons.menu_book_outlined, Icons.menu_book),
    _TabItem('视频', Icons.smart_display_outlined, Icons.smart_display),
    _TabItem('创作', Icons.library_books_outlined, Icons.library_books),
    _TabItem('分类', Icons.grid_view_outlined, Icons.grid_view),
    _TabItem('我的', Icons.person_outline, Icons.person),
  ];

  void _onTap(BuildContext context, WidgetRef ref, int index) {
    // 中间「创作」是新建作品的快捷入口：直接进入新建表单，不占用/切换 tab 分支。
    if (index == 2) {
      AuthGuard.pushProtected(context, ref, target: RoutePath.workUpload);
      return;
    }
    if (index == 4 && !AuthGuard.isLoggedIn(ref)) {
      if (ref.read(authControllerProvider).status == AuthStatus.unauthenticated) {
        context.go(AuthGuard.loginLocation(ref, RoutePath.profile));
      }
      return;
    }
    // 去掉创作分支后，其余四个 tab 映射到 0-3 四个分支（视觉 index>2 时减 1）。
    final branchIndex = index > 2 ? index - 1 : index;
    shell.goBranch(
      branchIndex,
      // 点击当前 tab 时回到该分支首页
      initialLocation: branchIndex == shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: i == 2
                        ? _CenterTab(
                            tab: _tabs[i],
                            // 创作是快捷动作，不存在常驻选中态。
                            active: false,
                            onTap: () => _onTap(context, ref, i),
                          )
                        : _TabButton(
                            tab: _tabs[i],
                            active: shell.currentIndex == (i > 2 ? i - 1 : i),
                            onTap: () => _onTap(context, ref, i),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem(this.label, this.icon, this.iconActive);
  final String label;
  final IconData icon;
  final IconData iconActive;
}

class _TabButton extends StatelessWidget {
  const _TabButton(
      {required this.tab, required this.active, required this.onTap});

  final _TabItem tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.text3;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(active ? tab.iconActive : tab.icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            tab.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 中间「创作」按钮：立体渐变圆形凸起样式，作为**新建作品**的快捷入口，点击直接
/// 进入新建表单（workUpload），不占用底部 tab 分支，故无常驻选中态。
///
/// 造型：44×44 圆形（内含 2.5px 纯白护圈与深湖蓝立体渐变），用 [Stack] + [Positioned]
/// 让其顶部高出底栏上沿 10px（`top: -10`），配柔和弥散投影；label 贴底对齐，
/// 与其余四个 tab 的文字基线保持一致。Stack 设 `Clip.none`，允许圆形溢出到 body 区。
class _CenterTab extends StatelessWidget {
  const _CenterTab(
      {required this.tab, required this.active, required this.onTap});

  final _TabItem tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = active ? AppColors.primary : AppColors.text3;
    return InkWell(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // label：位于圆形正下方、水平居中
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                tab.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: labelColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // 圆形凸起：top=-10 使其高出 56px 栏顶 10px，外包纯白护圈与弥散蓝影
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(active ? 0.32 : 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: active
                          ? const [Color(0xFF3264B8), Color(0xFF1A3868)]
                          : const [Color(0xFF2B59A2), Color(0xFF20437C)],
                    ),
                  ),
                  child: Icon(
                    active ? tab.iconActive : tab.icon,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
