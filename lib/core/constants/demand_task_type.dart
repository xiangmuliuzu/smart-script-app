// 任务广场（需求悬赏）任务类型常量：取值 / 中文名 / 主题色 / 交付口径。
import 'package:flutter/material.dart';

/// 与后端 TradeDemandService.TASK_TYPE_* 以及 PC 三端 utils/demand.js 的
/// TASK_TYPE_LABELS、TASK_TYPE_DELIVER_HINTS 同口径；被发布页的类型选择、
/// 广场筛选 chip、任务卡角标与详情页交付说明共用，避免多处硬编码漂移。
class DemandTaskType {
  DemandTaskType._();

  static const String script = 'script';
  static const String scriptStoryboard = 'script_storyboard';
  static const String storyboard = 'storyboard';

  static const List<String> values = <String>[script, scriptStoryboard, storyboard];

  static const Map<String, String> labels = <String, String>{
    script: '只征集剧本',
    scriptStoryboard: '剧本+分镜',
    storyboard: '提供剧本做分镜',
  };

  static const Map<String, Color> colors = <String, Color>{
    script: Color(0xFF3B82F6), // 只征集剧本 蓝
    scriptStoryboard: Color(0xFFF59E0B), // 剧本+分镜 橙
    storyboard: Color(0xFF22C55E), // 提供剧本做分镜 绿
  };

  /// 交付口径：接单方视角，说明这一类任务要交什么、走不走 AI 审核
  static const Map<String, String> deliverHints = <String, String>{
    script: '逐轮交付本人未上架的剧本作品，AI 剧本审核通过后进入平台人工验收',
    scriptStoryboard: '逐轮交付剧本作品，分镜以文件链接或交付说明随本轮一并提交，AI 剧本审核通过后进入人工验收',
    storyboard: '按平台提供的源剧本产出分镜：交付分镜文件或填写交付说明即可（作品可选），提交后直接进入人工验收',
  };

  static const Color fallbackColor = Color(0xFF6B7280);

  /// 后端列有默认值，但历史数据与旧客户端可能不带该字段，统一回落到「只征集剧本」
  static String normalize(String? value) => labels.containsKey(value) ? value! : script;

  static String labelOf(String? value) => labels[normalize(value)]!;
  static Color colorOf(String? value) => colors[normalize(value)] ?? fallbackColor;
  static String deliverHintOf(String? value) => deliverHints[normalize(value)]!;

  /// 仅「提供剧本做分镜」跳过 AI 剧本审核，且必须提供源剧本
  static bool isStoryboard(String? value) => normalize(value) == storyboard;
}
