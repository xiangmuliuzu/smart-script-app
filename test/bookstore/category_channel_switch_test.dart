// 分类页频道切换过渡的回归测试。
//
// 覆盖三点：
//   1. 切频道后的加载期间继续展示旧频道内容，不整屏闪回 loading；
//   2. 新数据到达后标签墙换成新频道内容；
//   3. 切回看过的频道直接命中缓存，即使重新请求不返回数据也能出内容。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/features/bookstore/data/bookstore_models.dart';
import 'package:script_app/features/bookstore/data/content_providers.dart';
import 'package:script_app/features/category/category_page.dart';

const _maleTag = '男频专属标签';
const _femaleTag = '女频专属标签';

CategoryNav _nav(int channelId, String tagName, {bool echoChannelId = true}) =>
    CategoryNav(
      channelId: echoChannelId ? channelId : null,
      channels: const [
        NavChannel(channelId: 1, channelName: '男生'),
        NavChannel(channelId: 2, channelName: '女生'),
      ],
      dimensions: [
        NavDimension(
          key: 'hot',
          name: '热门标签',
          groups: [
            NavGroup(groupName: '热门', items: [
              NavItem(itemType: 'tag', itemId: 10, itemName: tagName),
            ]),
          ],
        ),
      ],
    );

void main() {
  testWidgets('切换频道：加载中保留旧内容，数据到达后换成新频道，切回命中缓存',
      (tester) async {
    final female = Completer<CategoryNav>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryNavProvider.overrideWith((ref, channelId) {
            if (channelId == 2) return female.future;
            return Future.value(_nav(1, _maleTag));
          }),
        ],
        child: const MaterialApp(home: CategoryPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('男生'), findsOneWidget);
    expect(find.text(_maleTag), findsOneWidget);

    // 切到女生：数据还没回来
    await tester.tap(find.text('女生'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '切频道时不应整屏闪回 loading');
    expect(find.text(_maleTag), findsOneWidget,
        reason: '新数据到达前应继续展示旧频道内容');

    // 女生数据到达后换成新内容
    female.complete(_nav(2, _femaleTag));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_femaleTag), findsOneWidget);
    expect(find.text(_maleTag), findsNothing);

    // 切回男生：缓存直接命中，无需等待请求
    await tester.tap(find.text('男生'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_maleTag), findsOneWidget);
    expect(find.text(_femaleTag), findsNothing);
  });

  // 后端若不回 channelId，展示频道要回落到请求参数，否则标签墙的 key 不变、
  // 切换就不会触发淡出淡入。
  testWidgets('后端未回 channelId 时，新频道内容仍替换旧频道', (tester) async {
    final female = Completer<CategoryNav>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryNavProvider.overrideWith((ref, channelId) {
            if (channelId == 2) return female.future;
            return Future.value(_nav(1, _maleTag, echoChannelId: false));
          }),
        ],
        child: const MaterialApp(home: CategoryPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('女生'));
    await tester.pump();
    female.complete(_nav(2, _femaleTag, echoChannelId: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_femaleTag), findsOneWidget);
    expect(find.text(_maleTag), findsNothing);
  });
}
