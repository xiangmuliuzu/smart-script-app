import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/bookstore/data/bookstore_models.dart';

/// 榜单模型单元测试（接口 2.7.7：五榜 + {list, updatedAt} 载荷）。
void main() {
  test('RankingType 为五榜，of() 未知值回落 view', () {
    expect(
      RankingType.all.map((type) => type.code).toList(),
      <String>['view', 'favorite', 'sale', 'rating', 'new'],
    );
    expect(RankingType.of('new').label, '新书榜');
    expect(RankingType.of('unknown').code, 'view');
    expect(RankingType.of(null).code, 'view');
  });

  test('RankingPayload 解析 {list, updatedAt}', () {
    final payload = RankingPayload.fromJson(<String, dynamic>{
      'list': <dynamic>[
        <String, dynamic>{'rankNo': 1, 'workId': 1001, 'title': '测试作品', 'score': 12},
      ],
      'updatedAt': '2026-10-20 18:00:00',
    });

    expect(payload.list.length, 1);
    expect(payload.list.first.workId, 1001);
    expect(payload.list.first.title, '测试作品');
    expect(payload.list.first.score, 12);
    expect(payload.updatedAt, '2026-10-20 18:00:00');
  });

  test('RankingPayload 空/异常负载回落空集合与空时间', () {
    expect(RankingPayload.fromJson(null).list, isEmpty);
    expect(RankingPayload.fromJson(<String, dynamic>{'list': 'bad'}).list, isEmpty);
    expect(RankingPayload.fromJson(<String, dynamic>{'list': <dynamic>[]}).updatedAt, '');
  });
}
