import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/create/data/author_work_models.dart';

void main() {
  test('章节审核状态使用中文展示并区分试读条件', () {
    const approved = AuthorChapterItem(
      chapterId: 1,
      status: '0',
      isFree: true,
    );
    const draft = AuthorChapterItem(chapterId: 2, status: '1');
    const rejected = AuthorChapterItem(chapterId: 3, status: '2');

    expect(approved.statusLabel, '审核通过');
    expect(approved.isApproved, isTrue);
    expect(draft.statusLabel, '草稿');
    expect(draft.isApproved, isFalse);
    expect(rejected.statusLabel, '未通过审核');
    expect(rejected.isApproved, isFalse);
  });
}
