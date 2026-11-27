import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 章节页各类小组件（试读开关 / 四段切换 / 悬浮 AI 胶囊 / 空态卡 / 本章资料卡 / 底部状态栏）。
///
/// 拆出本章节页的公共组件，页面只负责状态与数据。

/// 试读开关行：仅「已发布且本章审核通过」时展示，切换即保存。
class ChapterTrialRow extends StatelessWidget {
  const ChapterTrialRow({
    super.key,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
      child: Row(
        children: [
          const Icon(Icons.lock_open_outlined, size: 15, color: AppColors.text3),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('设为试读章节（免费阅读）',
                style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
          ),
          Switch(
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: busy ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

/// 章节页顶部四段切换：概要 / 正文 / 分镜 / 本章资料。
class ChapterTabBar<T> extends StatelessWidget {
  const ChapterTabBar({
    super.key,
    required this.tabs,
    required this.current,
    required this.onChanged,
  });

  /// (值, 文案)。
  final List<(T, String)> tabs;
  final T current;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          for (final (tab, label) in tabs)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(tab),
                child: SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: current == tab ? AppColors.text1 : AppColors.text2,
                          fontWeight:
                              current == tab ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (current == tab)
                        Positioned(
                          bottom: 5,
                          child: Container(
                            width: 22,
                            height: 2,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 悬浮「AI 创作」胶囊。
class ChapterAiPill extends StatelessWidget {
  const ChapterAiPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(19),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 15, color: Colors.white),
            SizedBox(width: 6),
            Text('AI 创作', style: TextStyle(fontSize: 13, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// 正文 / 分镜空态卡：主按钮 ✦ AI 创作 + 次按钮「自己写」。
class ChapterEmptyCard extends StatelessWidget {
  const ChapterEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.secondaryLabel,
    this.onPrimary,
    this.onSecondary,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 36, 22, 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppColors.placeholder),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12.5, height: 1.75, color: AppColors.text3),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(primaryLabel, style: const TextStyle(fontSize: 13)),
              ),
              OutlinedButton(
                onPressed: onSecondary,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child:
                    Text(secondaryLabel, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (extra != null) ...[const SizedBox(height: 8), extra!],
        ],
      ),
    );
  }
}

/// 本章资料卡片：标题 + 可选操作 + 内容。
class ChapterMetaCard extends StatelessWidget {
  const ChapterMetaCard({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// 本章资料区块的空态提示。
class ChapterMetaEmpty extends StatelessWidget {
  const ChapterMetaEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style:
            const TextStyle(fontSize: 12, height: 1.7, color: AppColors.text3));
  }
}

/// 章节页底部状态栏：字数 / 行数 + 保存状态。
class ChapterStatusBar extends StatelessWidget {
  const ChapterStatusBar({
    super.key,
    required this.tabLabel,
    required this.detail,
    required this.saving,
    required this.dirty,
    required this.failed,
    required this.editable,
    required this.isFree,
    this.onRetry,
  });

  final String tabLabel;

  /// 已格式化的字数 / 行数（如「约 120 字」「12 行」）。
  final String detail;
  final bool saving;
  final bool dirty;
  final bool failed;
  final bool editable;
  final bool isFree;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final String status;
    final Color statusColor;
    final bool tappable;
    if (!editable) {
      status = '只读';
      statusColor = AppColors.text3;
      tappable = false;
    } else if (saving) {
      status = '保存中…';
      statusColor = AppColors.warning;
      tappable = false;
    } else if (failed) {
      status = '保存失败，点击重试';
      statusColor = AppColors.danger;
      tappable = onRetry != null;
    } else if (dirty) {
      status = '未保存';
      statusColor = AppColors.warning;
      tappable = false;
    } else {
      status = '已保存';
      statusColor = AppColors.success;
      tappable = false;
    }
    return Container(
      color: AppColors.card,
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Text('$tabLabel · $detail',
              style: const TextStyle(fontSize: 12, color: AppColors.text3)),
          if (isFree) ...[
            const SizedBox(width: 8),
            const Text('试读',
                style: TextStyle(fontSize: 11, color: AppColors.text1)),
          ],
          const Spacer(),
          GestureDetector(
            onTap: tappable ? onRetry : null,
            child: Text(status,
                style: TextStyle(fontSize: 12, color: statusColor)),
          ),
        ],
      ),
    );
  }
}
