import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// v3 作品资料的视觉区块（自绘，不引入图片资源、不虚构 AI 生图接口）。
///
/// - [CharacterPortrait]：竖版人物立绘（渐变底 + 矢量人物），人物卡 / 档案头卡使用；
/// - [CharacterAvatarChip]：圆形头像（关系图节点 / 本章出场胶囊）；
/// - [ThreeViewPanel]：正面 / 侧面 / 背面三视图线稿（与 PC v3 `ThreeViewGlyph` 同版式）；
/// - [ItemArtwork]：深色底物品图形（与 PC v3 `ItemGlyph` 同线稿）；
/// - [RelationBoard]：人物关系图（实线信任 / 虚线隐瞒，点节点看档案）。
///
/// 人物 / 物品都来自后端资料，图形按名称与顺序确定性绘制：同一个人物每次打开
/// 都是同一张图，不随刷新漂移。

/// 人物主色板（后端不下发颜色，按顺序取稳定色，与 PC v3 一致）。
const List<Color> kBlueprintPalette = <Color>[
  Color(0xFF4A7C75),
  Color(0xFF526A87),
  Color(0xFF9B7048),
  Color(0xFF7A5C78),
  Color(0xFF6B7F4A),
  Color(0xFF8A5A44),
];

Color blueprintColorAt(int index) =>
    kBlueprintPalette[index % kBlueprintPalette.length];

/// 人物底色：主色向白/黑插值出「上浅下深」的渐变对（对齐原型 `--bg1/--bg2`）。
({Color top, Color bottom}) characterBackground(int index) {
  final base = blueprintColorAt(index);
  return (
    top: Color.lerp(base, Colors.white, 0.42)!.withOpacity(0.92),
    bottom: base.withOpacity(0.95),
  );
}

bool _isFemale(dynamic gender) {
  final text = (gender ?? '').toString();
  return text.contains('女') || text.toLowerCase() == 'female';
}

/// 竖版人物立绘。
class CharacterPortrait extends StatelessWidget {
  const CharacterPortrait({
    super.key,
    required this.name,
    required this.index,
    this.gender = '',
    this.width = 100,
    this.height = 128,
    this.radius = 10,
    this.flag,
  });

  final String name;

  /// 人物在资料中的顺序（决定底色，稳定）。
  final int index;
  final String gender;
  final double width;
  final double height;
  final double radius;

  /// 左下角角标（如「已生成」）。
  final String? flag;

  @override
  Widget build(BuildContext context) {
    final bg = characterBackground(index);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _PortraitPainter(
                background: bg,
                longHair: _isFemale(gender),
              ),
            ),
            if (flag != null && flag!.isNotEmpty)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.42),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    flag!,
                    style: const TextStyle(fontSize: 9, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 圆形人物头像（关系图节点 / 本章出场胶囊）。
class CharacterAvatarChip extends StatelessWidget {
  const CharacterAvatarChip({
    super.key,
    required this.name,
    required this.index,
    this.gender = '',
    this.size = 46,
  });

  final String name;
  final int index;
  final String gender;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = characterBackground(index);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg.top, bg.bottom],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x29000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _PortraitPainter(
            background: bg,
            longHair: _isFemale(gender),
            portraitOnly: true,
          ),
        ),
      ),
    );
  }
}

/// 三视图：正面 / 侧面 / 背面（线稿，保持与 PC v3 同一造型）。
class ThreeViewPanel extends StatelessWidget {
  const ThreeViewPanel({
    super.key,
    required this.name,
    required this.index,
    this.height = 150,
  });

  final String name;
  final int index;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = blueprintColorAt(index);
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ThreeViewCell(
              caption: const ['正面', '侧面', '背面'][i],
              view: i,
              color: color,
              height: height,
            ),
          ),
        ],
      ],
    );
  }
}

class _ThreeViewCell extends StatelessWidget {
  const _ThreeViewCell({
    required this.caption,
    required this.view,
    required this.color,
    required this.height,
  });

  final String caption;
  final int view;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3F4F6), Color(0xFFE7E9EC)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            bottom: 18,
            child: CustomPaint(
              painter: _ThreeViewPainter(view: view, color: color),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 5,
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: AppColors.text3),
            ),
          ),
        ],
      ),
    );
  }
}

/// 物品图形：深色底 + 线稿。
class ItemArtwork extends StatelessWidget {
  const ItemArtwork({
    super.key,
    required this.icon,
    required this.name,
    this.size = 62,
    this.radius = 10,
  });

  final String icon;
  final String name;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF23272D), Color(0xFF3C444C), Color(0xFF5A626B)],
        ),
      ),
      child: CustomPaint(
        painter: ItemGlyphPainter(icon: icon, name: name),
      ),
    );
  }
}

/// 物品线稿（对齐 PC v3 `ItemGlyph`：磁带 / 收音机 / 钥匙 / 面具 / 纸页 / 通用）。
class ItemGlyphPainter extends CustomPainter {
  ItemGlyphPainter({required this.icon, this.name = ''});

  final String icon;
  final String name;

  @override
  void paint(Canvas canvas, Size size) {
    // 160x110 设计稿坐标，等比缩放到画布内居中。
    const design = Size(160, 110);
    final scale = math.min(size.width / design.width, size.height / design.height) * 0.86;
    canvas.save();
    canvas.translate(
      (size.width - design.width * scale) / 2,
      (size.height - design.height * scale) / 2,
    );
    canvas.scale(scale);

    final paper = Paint()..color = const Color(0xFFFBF9F4);
    final ink = Paint()
      ..color = const Color(0xFF1B1A18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final muted = Paint()
      ..color = const Color(0xFFDCD8CE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final teal = Paint()
      ..color = const Color(0xFF4A6C74)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final tealFill = Paint()..color = const Color(0xFF2C4A52);

    switch (icon) {
      case 'tape':
        final body = RRect.fromRectAndRadius(
            const Rect.fromLTWH(16, 20, 128, 72), const Radius.circular(7));
        canvas.drawRRect(body, paper);
        canvas.drawRRect(body, ink);
        canvas.drawRect(const Rect.fromLTWH(28, 30, 104, 38), teal..strokeWidth = 1.3);
        for (final cx in <double>[58, 102]) {
          canvas.drawCircle(Offset(cx, 49), 11, teal);
          canvas.drawCircle(Offset(cx, 49), 3.4, tealFill);
        }
        final spokes = Paint()
          ..color = const Color(0xFF2C4A52)
          ..strokeWidth = 1.1;
        for (final cx in <double>[58, 102]) {
          canvas
            ..drawLine(Offset(cx, 38), Offset(cx, 42), spokes)
            ..drawLine(Offset(cx, 56), Offset(cx, 60), spokes)
            ..drawLine(Offset(cx - 11, 49), Offset(cx - 7, 49), spokes)
            ..drawLine(Offset(cx + 7, 49), Offset(cx + 11, 49), spokes);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(56, 72, 48, 10), const Radius.circular(2)),
          muted,
        );
        final dot = Paint()..color = const Color(0xFF4A6C74);
        canvas
          ..drawCircle(const Offset(24, 84), 1.8, dot)
          ..drawCircle(const Offset(136, 84), 1.8, dot);
        break;
      case 'radio':
        canvas.drawLine(const Offset(112, 24), const Offset(142, 8), ink);
        final body = RRect.fromRectAndRadius(
            const Rect.fromLTWH(22, 24, 116, 62), const Radius.circular(6));
        canvas.drawRRect(body, paper);
        canvas.drawRRect(body, ink);
        canvas.drawRect(const Rect.fromLTWH(30, 32, 52, 46), muted);
        canvas.drawLine(const Offset(94, 34), const Offset(134, 34), teal);
        canvas.drawRect(const Rect.fromLTWH(90, 34, 40, 16), teal);
        final dial = Paint()
          ..color = const Color(0xFF1B1A18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        canvas.drawCircle(const Offset(100, 66), 8, dial);
        canvas.drawLine(const Offset(100, 66), const Offset(100, 60), teal);
        canvas.drawCircle(const Offset(122, 66), 4.5, dial);
        canvas
          ..drawLine(const Offset(30, 86), const Offset(38, 86), dial)
          ..drawLine(const Offset(122, 86), const Offset(130, 86), dial);
        break;
      case 'key':
        final ring = Paint()
          ..color = const Color(0xFF1B1A18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2;
        canvas.drawCircle(const Offset(38, 38), 15, ring);
        canvas.drawCircle(const Offset(38, 38), 6, teal);
        canvas.drawLine(const Offset(50, 50), const Offset(120, 92), ring);
        canvas.drawLine(const Offset(104, 82), const Offset(112, 74), ring);
        canvas.drawLine(const Offset(114, 88), const Offset(122, 80), ring);
        canvas.drawLine(const Offset(62, 58), const Offset(70, 52), teal);
        break;
      case 'mask':
        final mask = Path()
          ..moveTo(44, 24)
          ..quadraticBezierTo(80, 10, 116, 24)
          ..quadraticBezierTo(124, 70, 80, 96)
          ..quadraticBezierTo(36, 70, 44, 24)
          ..close();
        canvas.drawPath(mask, paper);
        canvas.drawPath(mask, ink);
        final feature = Paint()
          ..color = const Color(0xFF2C4A52)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(const Rect.fromLTWH(50, 34, 30, 18), 3.4, 1.4, false, feature);
        canvas.drawArc(const Rect.fromLTWH(80, 34, 30, 18), 4.6, -1.4, false, feature);
        canvas.drawArc(const Rect.fromLTWH(64, 62, 32, 18), 0.35, 2.4, false, teal);
        canvas.drawLine(const Offset(80, 26), const Offset(80, 62), muted);
        break;
      case 'note':
        final page = Path()
          ..moveTo(48, 22)
          ..lineTo(100, 22)
          ..lineTo(112, 34)
          ..lineTo(112, 94)
          ..quadraticBezierTo(112, 98, 108, 98)
          ..lineTo(48, 98)
          ..quadraticBezierTo(44, 98, 44, 94)
          ..lineTo(44, 26)
          ..quadraticBezierTo(44, 22, 48, 22)
          ..close();
        canvas.drawPath(page, paper);
        canvas.drawPath(page, muted);
        canvas
          ..drawLine(const Offset(100, 22), const Offset(100, 34), muted)
          ..drawLine(const Offset(100, 34), const Offset(112, 34), muted)
          ..drawLine(const Offset(56, 46), const Offset(100, 46), muted)
          ..drawLine(const Offset(56, 56), const Offset(100, 56), muted)
          ..drawLine(const Offset(56, 66), const Offset(90, 66), muted);
        final squiggle = Path()
          ..moveTo(56, 80)
          ..quadraticBezierTo(62, 74, 68, 80)
          ..quadraticBezierTo(74, 86, 80, 80)
          ..quadraticBezierTo(86, 74, 92, 80);
        canvas.drawPath(squiggle, teal..strokeWidth = 1.6);
        break;
      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(28, 26, 104, 60), const Radius.circular(4)),
          paper,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(28, 26, 104, 60), const Radius.circular(4)),
          muted,
        );
        canvas
          ..drawLine(const Offset(40, 42), const Offset(120, 42), muted)
          ..drawLine(const Offset(40, 54), const Offset(120, 54), muted)
          ..drawLine(const Offset(40, 66), const Offset(94, 66), muted);
        canvas.drawCircle(const Offset(118, 76), 12, teal);
        canvas
          ..drawLine(const Offset(112, 76), const Offset(124, 76), teal)
          ..drawLine(const Offset(118, 70), const Offset(118, 82), teal);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ItemGlyphPainter oldDelegate) =>
      oldDelegate.icon != icon || oldDelegate.name != name;
}

/// 人物关系图。
///
/// 布局与 PC v3 `RelationBoard` 一致：2 人对置、3 人三角、4 人以上圆心 + 圆环。
/// 实线＝合作/信任，虚线＝质疑/隐瞒；点击节点回调 [onSelect]。
class RelationBoard extends StatelessWidget {
  const RelationBoard({
    super.key,
    required this.characters,
    required this.edges,
    this.height = 236,
    this.onSelect,
    this.emptyText = '暂无人物关系，可让 AI 重新整理作品资料后再查看。',
    this.showLegend = true,
    this.legendLeft = '合作 / 信任',
    this.legendRight = '质疑 / 隐瞒',
  });

  final List<RelationCharacter> characters;
  final List<RelationEdge> edges;
  final double height;
  final ValueChanged<String>? onSelect;
  final String emptyText;
  final bool showLegend;
  final String legendLeft;
  final String legendRight;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return _RelationEmpty(
        text: emptyText,
        showLegend: showLegend,
        legendLeft: legendLeft,
        legendRight: legendRight,
      );
    }
    final nodes = _layout(characters.take(8).toList());
    final byKey = {for (final node in nodes) node.character.key: node};
    final drawable = <({RelationNode from, RelationNode to, RelationEdge edge})>[];
    for (final edge in edges) {
      final from = byKey[edge.a];
      final to = byKey[edge.b];
      if (from == null || to == null) continue;
      drawable.add((from: from, to: to, edge: edge));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFAFAFA), Color(0xFFF3F4F6)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RelationLinesPainter(
                      nodes: nodes,
                      edges: drawable,
                    ),
                  ),
                ),
                for (final link in drawable) _edgeLabel(link),
                for (final node in nodes) _node(context, node),
              ],
            ),
          ),
        ),
        if (showLegend) _legend(),
      ],
    );
  }

  Widget _edgeLabel(
      ({RelationNode from, RelationNode to, RelationEdge edge}) link) {
    final x = (link.from.x + link.to.x) / 2;
    final y = (link.from.y + link.to.y) / 2;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment(x * 2 - 1, y * 2 - 1),
        child: IgnorePointer(
          child: Transform.translate(
            offset: const Offset(0, -1),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 120),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                link.edge.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: AppColors.text2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _node(BuildContext context, RelationNode node) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment(node.x * 2 - 1, node.y * 2 - 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect == null ? null : () => onSelect!(node.character.key),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CharacterAvatarChip(
                name: node.character.name,
                index: node.character.index,
                gender: node.character.gender,
                size: 46,
              ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxWidth: 96),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 3,
                        offset: Offset(0, 1)),
                  ],
                ),
                child: Text(
                  node.character.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.text1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          _LegendItem(label: legendLeft, dash: false),
          const SizedBox(width: 16),
          _LegendItem(label: legendRight, dash: true),
        ],
      ),
    );
  }

  /// 位置为 0~1 的相对坐标，与 PC v3 同一套布局。
  static List<RelationNode> _layout(List<RelationCharacter> characters) {
    final count = characters.length;
    final positions = <({double x, double y})>[];
    if (count == 1) {
      positions.add((x: 0.5, y: 0.5));
    } else if (count == 2) {
      positions
        ..add((x: 0.28, y: 0.5))
        ..add((x: 0.72, y: 0.5));
    } else if (count == 3) {
      positions
        ..add((x: 0.5, y: 0.26))
        ..add((x: 0.24, y: 0.76))
        ..add((x: 0.76, y: 0.76));
    } else {
      positions.add((x: 0.5, y: 0.5));
      const radius = 0.34;
      for (var index = 1; index < count; index++) {
        final angle = math.pi * 2 * (index - 1) / (count - 1) - math.pi / 2;
        positions.add((
          x: 0.5 + math.cos(angle) * radius,
          y: 0.5 + math.sin(angle) * radius * 0.82,
        ));
      }
    }
    return [
      for (var index = 0; index < count; index++)
        RelationNode(
          character: characters[index],
          x: positions[index].x,
          y: positions[index].y,
        ),
    ];
  }
}

/// 关系图节点（人物 + 相对位置 0~1）。
class RelationNode {
  const RelationNode({
    required this.character,
    required this.x,
    required this.y,
  });

  final RelationCharacter character;
  final double x;
  final double y;
}

/// 关系图人物（key/姓名/性别/色板下标）。
class RelationCharacter {
  const RelationCharacter({
    required this.key,
    required this.name,
    this.gender = '',
    this.index = 0,
    this.role = '',
  });

  final String key;
  final String name;
  final String gender;
  final int index;
  final String role;
}

/// 关系边。
class RelationEdge {
  const RelationEdge({
    required this.a,
    required this.b,
    required this.label,
    this.dash = false,
  });

  final String a;
  final String b;
  final String label;
  final bool dash;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.dash});

  final String label;
  final bool dash;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 6,
          child: CustomPaint(painter: _DashLinePainter(dash: dash)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.text3)),
      ],
    );
  }
}

class _DashLinePainter extends CustomPainter {
  _DashLinePainter({required this.dash});

  final bool dash;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dash ? AppColors.text3 : AppColors.text2
      ..strokeWidth = 1.5;
    final y = size.height / 2;
    if (!dash) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _DashLinePainter oldDelegate) =>
      oldDelegate.dash != dash;
}

class RelationBoardEmpty extends StatelessWidget {
  const RelationBoardEmpty({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => _RelationEmpty(
        text: text,
        showLegend: true,
        legendLeft: '合作 / 信任',
        legendRight: '质疑 / 隐瞒',
      );
}

class _RelationEmpty extends StatelessWidget {
  const _RelationEmpty({
    required this.text,
    required this.showLegend,
    required this.legendLeft,
    required this.legendRight,
  });

  final String text;
  final bool showLegend;
  final String legendLeft;
  final String legendRight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12, height: 1.7, color: AppColors.text3),
          ),
        ),
        if (showLegend)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                _LegendItem(label: legendLeft, dash: false),
                const SizedBox(width: 16),
                _LegendItem(label: legendRight, dash: true),
              ],
            ),
          ),
      ],
    );
  }
}

/// 关系连线（画在节点下层）。
class _RelationLinesPainter extends CustomPainter {
  _RelationLinesPainter({required this.nodes, required this.edges});

  final List<RelationNode> nodes;

  /// from/to 已按 key 解析为节点，null 边在构建时已剔除。
  final List<({RelationNode from, RelationNode to, RelationEdge edge})> edges;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in edges) {
      final from = Offset(link.from.x * size.width, link.from.y * size.height);
      final to = Offset(link.to.x * size.width, link.to.y * size.height);
      final paint = Paint()
        ..color = link.edge.dash ? AppColors.text3 : AppColors.text2
        ..strokeWidth = link.edge.dash ? 1.4 : 1.6
        ..strokeCap = StrokeCap.round;
      if (!link.edge.dash) {
        canvas.drawLine(from, to, paint);
        continue;
      }
      final delta = to - from;
      final length = delta.distance;
      if (length == 0) continue;
      final unit = delta / length;
      var travelled = 0.0;
      while (travelled < length) {
        final start = from + unit * travelled;
        final end = from + unit * math.min(travelled + 5, length);
        canvas.drawLine(start, end, paint);
        travelled += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RelationLinesPainter oldDelegate) => true;
}

// ================================================================
// 人物立绘（填充风）
// ================================================================

/// 竖版人物：渐变底 + 上半身人物（深色外套与头发，柔和肤色）。
///
/// 坐标按 120×180 设计稿绘制，等比缩放；[portraitOnly] 时放大头部用于圆形头像。
class _PortraitPainter extends CustomPainter {
  _PortraitPainter({
    required this.background,
    required this.longHair,
    this.portraitOnly = false,
  });

  final ({Color top, Color bottom}) background;
  final bool longHair;
  final bool portraitOnly;

  static const Color _skin = Color(0xFFE3C4AC);
  static const Color _skinShade = Color(0xFFCBA98F);
  static const Color _hair = Color(0xFF26201C);
  static const Color _coat = Color(0xFF3A3A40);
  static const Color _coatShade = Color(0xFF24242A);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [background.top, background.bottom],
        ).createShader(rect),
    );
    // 背景光晕：人物背后的柔光，避免纯平。
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.18),
      size.shortestSide * 0.42,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.22), Colors.white.withOpacity(0)],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.78, size.height * 0.18),
          radius: size.shortestSide * 0.42,
        )),
    );

    final scale = portraitOnly
        ? size.width / 78
        : math.min(size.width / 120, size.height / 180);
    canvas.save();
    if (portraitOnly) {
      // 圆形头像：以头部为中心裁切。
      canvas.translate(size.width / 2 - 60 * scale, size.height * 0.08);
    } else {
      canvas.translate(
        (size.width - 120 * scale) / 2,
        size.height - 180 * scale,
      );
    }
    canvas.scale(scale);

    if (!portraitOnly) {
      canvas.drawOval(
        const Rect.fromLTRB(22, 168, 98, 178),
        Paint()..color = Colors.black.withOpacity(0.10),
      );
    }

    final coat = Paint()..color = _coat;
    final skin = Paint()..color = _skin;
    const skinShade = _skinShade;
    final hair = Paint()..color = _hair;

    // 长发先铺在身后。
    if (longHair) {
      final back = Path()
        ..moveTo(38, 64)
        ..cubicTo(38, 44, 48, 36, 60, 36)
        ..cubicTo(73, 36, 83, 44, 83, 64)
        ..lineTo(87, 124)
        ..cubicTo(84, 129, 77, 129, 74, 123)
        ..lineTo(72, 88)
        ..lineTo(48, 88)
        ..lineTo(46, 123)
        ..cubicTo(43, 129, 36, 129, 33, 124)
        ..close();
      canvas.drawPath(back, hair);
    }

    // 肩膀与外套。
    final shoulders = Path()
      ..moveTo(25, 180)
      ..cubicTo(26, 130, 36, 110, 60, 108)
      ..cubicTo(84, 110, 94, 130, 95, 180)
      ..close();
    canvas.drawPath(shoulders, coat);
    canvas.drawLine(
      const Offset(60, 108),
      const Offset(60, 180),
      Paint()
        ..color = _coatShade
        ..strokeWidth = 2,
    );
    final leftShade = Path()
      ..moveTo(41, 112)
      ..cubicTo(37, 134, 36, 158, 36, 180)
      ..lineTo(29, 180)
      ..cubicTo(29, 152, 32, 128, 37, 112)
      ..close();
    canvas.drawPath(leftShade, Paint()..color = Colors.black.withOpacity(0.12));

    // 脖子。
    final neck = Path()
      ..moveTo(50, 96)
      ..lineTo(70, 96)
      ..lineTo(70, 112)
      ..cubicTo(64, 117, 56, 117, 50, 112)
      ..close();
    canvas.drawPath(neck, skin);
    canvas.drawPath(
      Path()
        ..moveTo(50, 96)
        ..lineTo(70, 96)
        ..lineTo(70, 103)
        ..cubicTo(64, 107, 56, 107, 50, 103)
        ..close(),
      Paint()..color = Colors.black.withOpacity(0.12),
    );

    // 头部。
    canvas.drawOval(const Rect.fromLTRB(37, 47, 83, 97), skin);
    canvas.drawOval(const Rect.fromLTRB(33.6, 70, 40.4, 80.4), skin);
    canvas.drawOval(const Rect.fromLTRB(79.6, 70, 86.4, 80.4), skin);

    // 头发（前额 + 两侧）。
    final frontHair = Path()
      ..moveTo(37, 72)
      ..cubicTo(37, 50, 47, 42, 60, 42)
      ..cubicTo(74, 42, 84, 50, 84, 72)
      ..cubicTo(84, 62, 76, 55, 66, 55)
      ..cubicTo(59, 55, 54, 58, 50, 63)
      ..cubicTo(48, 57, 41, 58, 39, 67)
      ..cubicTo(38, 69, 37, 71, 37, 72)
      ..close();
    canvas.drawPath(frontHair, hair);
    if (longHair) {
      final leftCurl = Path()
        ..moveTo(35, 70)
        ..cubicTo(31, 86, 30, 104, 33, 120)
        ..cubicTo(37, 124, 43, 123, 45, 117)
        ..cubicTo(43, 101, 43, 82, 45, 72)
        ..close();
      final rightCurl = Path()
        ..moveTo(85, 70)
        ..cubicTo(89, 86, 90, 104, 87, 120)
        ..cubicTo(83, 124, 77, 123, 75, 117)
        ..cubicTo(77, 101, 77, 82, 75, 72)
        ..close();
      canvas.drawPath(leftCurl, hair);
      canvas.drawPath(rightCurl, hair);
    } else {
      final leftSide = Path()
        ..moveTo(37, 70)
        ..cubicTo(35, 78, 36, 85, 40, 88)
        ..cubicTo(39, 80, 39, 74, 41, 69)
        ..close();
      final rightSide = Path()
        ..moveTo(83, 70)
        ..cubicTo(85, 78, 84, 85, 80, 88)
        ..cubicTo(81, 80, 81, 74, 79, 69)
        ..close();
      canvas
        ..drawPath(leftSide, hair)
        ..drawPath(rightSide, hair);
    }

    // 五官。
    final ink = Paint()
      ..color = const Color(0xFF2A2320)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(49, 67), const Offset(56, 66), ink)
      ..drawLine(const Offset(64, 66), const Offset(71, 67), ink)
      ..drawOval(const Rect.fromLTRB(50.6, 70.8, 54.4, 75.2),
          Paint()..color = const Color(0xFF2A2320))
      ..drawOval(const Rect.fromLTRB(65.6, 70.8, 69.4, 75.2),
          Paint()..color = const Color(0xFF2A2320));
    canvas.drawPath(
      Path()
        ..moveTo(60, 75)
        ..lineTo(59, 83)
        ..lineTo(62, 83),
      Paint()
        ..color = const Color(0xFF8A6A58)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(55, 89)
        ..quadraticBezierTo(60, 91.6, 65, 89),
      Paint()
        ..color = Colors.black.withOpacity(0.32)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    // 颈部高光与衣领。
    canvas.drawPath(
      Path()
        ..moveTo(50, 109)
        ..lineTo(60, 121)
        ..lineTo(70, 109)
        ..lineTo(73, 112)
        ..cubicTo(67, 121, 53, 121, 47, 112)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.12),
    );
    canvas.drawPath(
      Path()
        ..moveTo(41, 58)
        ..cubicTo(37, 76, 41, 96, 52, 105),
      Paint()
        ..color = Colors.white.withOpacity(0.16)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    // 柔和的下颌阴影。
    canvas.drawOval(
      const Rect.fromLTRB(46, 86, 74, 98),
      Paint()
        ..color = skinShade.withOpacity(0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PortraitPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.longHair != longHair ||
      oldDelegate.portraitOnly != portraitOnly;
}

/// 三视图线稿（正面 / 侧面 / 背面），与 PC v3 `ThreeViewGlyph` 同一造型。
class _ThreeViewPainter extends CustomPainter {
  _ThreeViewPainter({required this.view, required this.color});

  /// 0 正面 / 1 侧面 / 2 背面。
  final int view;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const design = Size(120, 200);
    final scale = math.min(size.width / design.width, size.height / design.height);
    canvas.save();
    canvas.translate(
      (size.width - design.width * scale) / 2,
      (size.height - design.height * scale) / 2,
    );
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (view == 1) {
      canvas
        ..drawCircle(const Offset(62, 30), 16, paint)
        ..drawPath(
          Path()
            ..moveTo(79, 27)
            ..lineTo(88, 33)
            ..lineTo(79, 39),
          paint,
        )
        ..drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(50, 62, 22, 62), const Radius.circular(10)),
          paint,
        )
        ..drawLine(const Offset(56, 70), const Offset(46, 120), paint)
        ..drawLine(const Offset(58, 124), const Offset(48, 188), paint)
        ..drawLine(const Offset(66, 126), const Offset(62, 188), paint);
    } else if (view == 2) {
      canvas
        ..drawCircle(const Offset(60, 30), 16, paint)
        ..drawPath(
          Path()
            ..moveTo(46, 24)
            ..quadraticBezierTo(60, 10, 74, 24),
          paint,
        )
        ..drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(42, 62, 36, 62), const Radius.circular(11)),
          paint,
        )
        ..drawLine(const Offset(44, 70), const Offset(32, 120), paint)
        ..drawLine(const Offset(76, 70), const Offset(88, 120), paint)
        ..drawLine(const Offset(52, 124), const Offset(48, 188), paint)
        ..drawLine(const Offset(68, 124), const Offset(72, 188), paint);
      final spine = Paint()
        ..color = color.withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(60, 66), const Offset(60, 120), spine);
    } else {
      canvas
        ..drawCircle(const Offset(60, 30), 16, paint)
        ..drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(42, 62, 36, 62), const Radius.circular(11)),
          paint,
        )
        ..drawLine(const Offset(44, 70), const Offset(32, 120), paint)
        ..drawLine(const Offset(76, 70), const Offset(88, 120), paint)
        ..drawLine(const Offset(52, 124), const Offset(48, 188), paint)
        ..drawLine(const Offset(68, 124), const Offset(72, 188), paint);
      final detail = Paint()
        ..color = color.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(52, 74), const Offset(68, 74), detail);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ThreeViewPainter oldDelegate) =>
      oldDelegate.view != view || oldDelegate.color != color;
}
