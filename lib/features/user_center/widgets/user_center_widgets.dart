import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A5 用户中心公共组件。
///
/// 抽离原因：资料页、实名页、账号安全、换绑、消息与反馈页共用同一批
/// 「表单行 / 分组 / 步骤卡 / 状态标签」结构，按 `rules.md` §3.2 的组件复用原则
/// 统一封装，避免页面级复制粘贴导致样式漂移。

/// 表单/信息行：左侧固定宽度标签 + 右侧内容。
class UserFieldRow extends StatelessWidget {
  const UserFieldRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = 84,
    this.showDivider = true,
  });

  final String label;
  final Widget child;
  final double labelWidth;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.divider, width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: const TextStyle(color: AppColors.text2)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 只读键值行（用于状态展示）。
class UserInfoLine extends StatelessWidget {
  const UserInfoLine({super.key, required this.label, required this.value, this.labelWidth = 76});

  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.text1, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// 白底分组容器（每组之间留 12 间距，与「我的」页视觉一致）。
class UserCard extends StatelessWidget {
  const UserCard({super.key, required this.children, this.margin});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      margin: margin,
      child: Column(children: children),
    );
  }
}

/// 可点击入口行：图标 + 文案 + 可选右侧文字 / 角标 + 右箭头。
class UserEntryRow extends StatelessWidget {
  const UserEntryRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingText,
    this.trailingColor,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailingText;
  final Color? trailingColor;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.text1)),
            ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: TextStyle(fontSize: 13, color: trailingColor ?? AppColors.text3),
              ),
            if (badge > 0) ...[
              const SizedBox(width: 8),
              _Badge(count: badge),
            ],
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

/// 步骤卡（换绑手机号等多步流程使用）。
class UserStepCard extends StatelessWidget {
  const UserStepCard({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.done,
    required this.child,
  });

  final int index;
  final String title;
  final String subtitle;
  final bool active;
  final bool done;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.divider,
          width: active ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: done ? AppColors.success : AppColors.primaryTint,
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '$index',
                        style: const TextStyle(fontSize: 12, color: AppColors.primary),
                      ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: AppColors.text3, fontSize: 12)),
          const SizedBox(height: 12),
          if (active) child,
        ],
      ),
    );
  }
}

/// 小标签（消息类型、反馈状态等）。
class UserStatusChip extends StatelessWidget {
  const UserStatusChip({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

/// 表单提交按钮：统一 loading 态，避免每个页面各写一遍进度圈。
class UserSubmitButton extends StatelessWidget {
  const UserSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
