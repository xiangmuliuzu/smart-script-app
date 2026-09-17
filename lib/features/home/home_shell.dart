import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

/// 主框架的底部导航容器（对应 UI 原型 `.tabbar` 五格平铺 + 中间"+"凸起）。
///
/// 五个分支由 [StatefulNavigationShell] 管理，切 tab 会保留各自导航栈。
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = <_TabItem>[
    _TabItem('书城', Icons.menu_book_outlined, Icons.menu_book),
    _TabItem('漫剧', Icons.smart_display_outlined, Icons.smart_display),
    _TabItem('创作', Icons.add, Icons.add),
    _TabItem('分类', Icons.grid_view_outlined, Icons.grid_view),
    _TabItem('我的', Icons.person_outline, Icons.person),
  ];

  void _onTap(int index) {
    shell.goBranch(
      index,
      // 点击当前 tab 时回到该分支首页
      initialLocation: index == shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                            active: shell.currentIndex == i,
                            onTap: () => _onTap(i),
                          )
                        : _TabButton(
                            tab: _tabs[i],
                            active: shell.currentIndex == i,
                            onTap: () => _onTap(i),
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
          Text(tab.label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

/// 中间"+"创作按钮：圆形凸起样式。
class _CenterTab extends StatelessWidget {
  const _CenterTab(
      {required this.tab, required this.active, required this.onTap});

  final _TabItem tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.primary : AppColors.primaryTint,
            border: Border.all(color: AppColors.primary),
          ),
          child: Icon(
            tab.icon,
            color: active ? Colors.white : AppColors.primary,
            size: 24,
          ),
        ),
      ),
    );
  }
}
