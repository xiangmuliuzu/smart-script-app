import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../data/promotion_models.dart';

/// 金额展示：整数省略小数，非整数保留两位。
String formatPromotionMoney(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

/// 日期文案：后端下发 `yyyy-MM-dd HH:mm:ss`，这里只取 MM-dd。
String formatPromotionMonthDay(String? value) {
  if (value == null || value.isEmpty) return '';
  final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (parsed == null) {
    return value.length >= 10 ? value.substring(5, 10) : value;
  }
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(parsed.month)}-${two(parsed.day)}';
}

/// 申请状态色（按后端派生文案映射，避免状态枚举扩散到各页面）。
Color promotionStatusColor(PromotionApplication item) {
  switch (item.displayStatus) {
    case '待审核':
      return AppColors.warning;
    case '待支付':
      return AppColors.accent;
    case '待生效':
      return AppColors.primary;
    case '投放中':
      return AppColors.success;
    case '已驳回':
      return AppColors.danger;
    default:
      return AppColors.text3;
  }
}

Color promotionSlotStateColor(String state) {
  switch (state) {
    case 'idle':
      return AppColors.success;
    case 'locked':
      return AppColors.accent;
    case 'active':
      return AppColors.primary;
    case 'reserved':
      return AppColors.warning;
    case 'missing_material':
      return AppColors.danger;
    default:
      return AppColors.text3;
  }
}

/// 推广规则文案（首页与申请向导共用）。
const List<String> promotionRuleLines = [
  '仅本人已上架的作品可申请推广，未上架作品不参与审核。',
  '同一作品在同一时段内只能占用一个推广位次。',
  '提交后进入人工审核；审核通过即锁定位次 48 小时，逾期未支付自动释放。',
  '投放开始后不支持退款与改期，请确认作品与时段后再提交。',
  '首页热门精选第 1–6 位直接展示，第 7 位起需点击「更多」后可见，价格更低。',
];

/// 推广规则底部弹层。
void showPromotionRulesSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '推广规则',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 12),
            for (final line in promotionRuleLines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.text2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 淡彩状态胶囊。
class PromotionStatusChip extends StatelessWidget {
  const PromotionStatusChip({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.25,
        ),
      ),
    );
  }
}

/// 我的推广记录卡片：作品信息 + 金额 + 状态 + 单一主操作（去支付 / 查看）。
class PromotionOrderCard extends StatelessWidget {
  const PromotionOrderCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onPay,
  });

  final PromotionApplication item;
  final VoidCallback onTap;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final statusColor = promotionStatusColor(item);
    final lockText = item.canPay ? item.lockRemainText : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.r)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.r),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WorkCover(
                      url: item.workCover ?? '',
                      title: item.workTitle,
                      width: 46,
                      height: 60,
                      radius: 7,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.workTitle.isEmpty ? '未命名作品' : item.workTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryTint,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.slotTypeLabel,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '第 ${item.slotNo} 位 · ${_positionHint(item)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _periodText(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.text3,
                                  ),
                                ),
                              ),
                              if (lockText != null) ...[
                                const Icon(
                                  Icons.timer_outlined,
                                  size: 11,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '剩余 $lockText',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: AppColors.divider),
                ),
                Row(
                  children: [
                    Text(
                      '¥${formatPromotionMoney(item.amount)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _amountHint(item),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.text3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PromotionStatusChip(
                      label: item.displayStatus,
                      color: statusColor,
                    ),
                    const Spacer(),
                    if (onPay != null && item.canPay)
                      _MiniButton(
                        label: '去支付',
                        foreground: Colors.white,
                        background: AppColors.accent,
                        onPressed: onPay!,
                      )
                    else
                      _MiniButton(
                        label: '查看',
                        foreground: AppColors.primary,
                        background: null,
                        onPressed: onTap,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _positionHint(PromotionApplication item) {
    switch (item.slotType) {
      case 'hot':
        return item.slotNo <= 6 ? '首页可见' : '更多页可见';
      case 'search':
        return '搜索结果';
      case 'banner':
        return '首页轮播';
      default:
        return '推广位';
    }
  }

  static String _amountHint(PromotionApplication item) {
    if (item.canPay) return '应付';
    if (item.payStatus == 'paid') return '已支付';
    return '预计';
  }

  static String _periodText(PromotionApplication item) {
    final start = formatPromotionMonthDay(item.startTime);
    final end = formatPromotionMonthDay(item.endTime);
    if (start.isEmpty || end.isEmpty) return '时段待审核后确认';
    return '$start 至 $end · ${item.days} 天';
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.foreground,
    required this.background,
    required this.onPressed,
  });

  final String label;
  final Color foreground;
  final Color? background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: background ?? Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: background == null ? AppColors.primary : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// 位次选择卡片（2 列网格）：位次 + 展示位置标签 + 单价 + 可投状态。
class PromotionSlotCard extends StatelessWidget {
  const PromotionSlotCard({
    super.key,
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  final PromotionSlotItem slot;
  final bool selected;
  final VoidCallback onTap;

  String get _positionTag {
    switch (slot.slotType) {
      case 'hot':
        return slot.slotNo <= 6 ? '首页' : '更多页';
      case 'search':
        return '搜索页';
      case 'banner':
        return '轮播';
      default:
        return '';
    }
  }

  String get _stateText {
    if (!slot.enabled) return '已停用';
    switch (slot.state) {
      case 'locked':
        return '待支付锁定';
      case 'active':
        final end = formatPromotionMonthDay(slot.current?.endTime);
        return end.isEmpty ? '投放中' : '已占用至 $end';
      case 'reserved':
        return '已预约';
      case 'missing_material':
        return '待补素材';
      case 'idle':
        final nextStart = formatPromotionMonthDay(slot.next?.startTime);
        return nextStart.isEmpty ? '可投' : '$nextStart 起可投';
      default:
        return slot.stateLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = !slot.selectable;
    final background = selected
        ? AppColors.primaryTint
        : blocked
            ? AppColors.fill
            : AppColors.card;
    final stateColor = blocked ? AppColors.text3 : AppColors.success;

    return Opacity(
      opacity: blocked ? 0.62 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.divider,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '第 ${slot.slotNo} 位',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.primary : AppColors.text1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: slot.slotNo <= 6 && slot.slotType == 'hot'
                            ? AppColors.accentSoft
                            : AppColors.fill,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _positionTag,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.4,
                          color: slot.slotNo <= 6 && slot.slotType == 'hot'
                              ? AppColors.accent
                              : AppColors.text3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '¥${formatPromotionMoney(slot.pricePerDay)}/天',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _stateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: stateColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
