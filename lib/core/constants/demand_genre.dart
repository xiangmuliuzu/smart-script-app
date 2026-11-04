import 'package:flutter/material.dart';

/// 任务广场（需求悬赏）题材常量：id / 中文名 / 主题色。
///
/// 与后端 sys_genre 保持一致；同时被 demand_post_page 的下拉与
/// demand_list_page 的分类 chip / 卡片色条使用，避免多处硬编码漂移。
class DemandGenre {
  DemandGenre._();

  static const Map<int, String> labels = <int, String>{
    1: '都市',
    2: '古装',
    3: '玄幻',
    4: '悬疑',
    5: '甜宠',
    6: '励志',
    7: '其他',
  };

  static const Map<int, Color> colors = <int, Color>{
    1: Color(0xFF3B82F6), // 都市 蓝
    2: Color(0xFFA855F7), // 古装 紫
    3: Color(0xFFF97316), // 玄幻 橙
    4: Color(0xFF0F172A), // 悬疑 深靛
    5: Color(0xFFEC4899), // 甜宠 玫红
    6: Color(0xFF22C55E), // 励志 绿
    7: Color(0xFF6B7280), // 其他 中性灰
  };

  static const Color fallbackColor = Color(0xFF6B7280);

  static String labelOf(int? id) => labels[id ?? 0] ?? '未分类';
  static Color colorOf(int? id) => colors[id ?? 0] ?? fallbackColor;
}
