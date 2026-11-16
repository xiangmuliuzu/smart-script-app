import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/ai/data/outline_sections.dart';

void main() {
  test('同名段重复出现时只保留最新一份', () {
    const text = '故事简介：\n第一版简介\n主要人物：\n甲：旧设定\n'
        '故事简介：\n第二版简介\n主要人物：\n甲：新设定';
    final sections = splitOutlineSections(text);
    expect(sections.summary, '第二版简介');
    expect(sections.summary.contains('第一版'), isFalse);
    expect(sections.characters.trim(), '甲：新设定');
  });

  test('同名人物只给状态变化短句时追加而非替换原设定', () {
    const base = '顾守山（56岁/男）：屯堡地戏班主，矮壮、嗓门大，走路带风，'
        '左手虎口有一道被面具篾条划的旧疤，说话像敲锣，爱用戏文里的腔调压人。\n'
        '罗小穗：县文化馆干事，做事细，随身带录音笔。';
    const patch = '顾守山（状态变化）：面具丢了，人沉下来。';
    final merged = mergeCharacterText(base, patch);
    expect(merged.contains('矮壮'), isTrue);
    expect(merged.contains('状态变化'), isTrue);
  });
}
