import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/trade/data/demand_repository.dart';
import 'package:script_app/features/trade/data/trade_models.dart';
import '../support/scripted_api.dart';

/// 验收查阅交付作品：发布者看本轮已交集数的正文。
///
/// 交付作品一定未上架，读者接口取不到，只能走 trade 域的 deliverable-work；
/// 集数边界由后端下发，这里锁两件事：请求打到哪个地址、readable=false 的集读不到正文。
Map<String, dynamic> _chapter(int no, {required bool readable}) => <String, dynamic>{
      'chapterId': no,
      'chapterNo': no,
      'chapterTitle': '第$no集',
      'wordCount': 100 * no,
      'readable': readable,
      if (readable) 'content': '第$no集正文',
    };

void main() {
  test('查看交付内容打的是 trade 域 deliverable-work，不是 content 读者接口', () async {
    final api = ScriptedApi();
    api.handle('/trade/demand/56/stage/80/deliverable-work',
        (_) => Envelope.ok(<String, dynamic>{
              'workId': 92,
              'title': '待验收的剧本',
              'episodeCount': 3,
              'episodeTo': 2,
              'stageOrder': 1,
              'chapters': <Map<String, dynamic>>[
                _chapter(1, readable: true),
                _chapter(2, readable: true),
                _chapter(3, readable: false),
              ],
            }));
    final repo = DemandRepository(ApiClient(api.buildDio()));

    final view = await repo.stageDeliverableView(56, 80);

    expect(api.requests.map((request) => request.path),
        ['/trade/demand/56/stage/80/deliverable-work']);
    expect(view.title, '待验收的剧本');
    expect(view.episodeTo, 2);
    expect(view.readableCount, 2);
  });

  test('超出本轮集数的集只留标题，正文为空且不可展开', () async {
    final view = StageDeliverableView.fromJson(<String, dynamic>{
      'workId': 92,
      'episodeTo': 1,
      'chapters': <Map<String, dynamic>>[
        _chapter(1, readable: true),
        _chapter(2, readable: false),
      ],
    });

    expect(view.chapters[0].readable, true);
    expect(view.chapters[0].content, '第1集正文');
    expect(view.chapters[1].readable, false);
    expect(view.chapters[1].content, isNull);
    // 标题仍要留着，发布者要知道后面还有几集没交
    expect(view.chapters[1].displayTitle, '第2集');
    expect(view.readableCount, 1);
  });

  test('readable 兼容网关把布尔变成 1/"1"/"true" 的情况', () {
    for (final raw in <dynamic>[true, 1, '1', 'true']) {
      final chapter =
          DeliverableChapter.fromJson(<String, dynamic>{'chapterId': 1, 'readable': raw});
      expect(chapter.readable, true, reason: 'readable=$raw 应判为可读');
    }
    for (final raw in <dynamic>[false, 0, '0', 'false', null]) {
      final chapter =
          DeliverableChapter.fromJson(<String, dynamic>{'chapterId': 1, 'readable': raw});
      expect(chapter.readable, false, reason: 'readable=$raw 应判为不可读');
    }
  });

  test('后端没给 chapters 时回落空列表，页面不炸', () {
    final view = StageDeliverableView.fromJson(<String, dynamic>{
      'workId': 92,
      'title': '未命名作品',
    });

    expect(view.chapters, isEmpty);
    expect(view.readableCount, 0);
    expect(view.episodeTo, isNull);
  });
}
