import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'author_work_providers.dart';
import 'create_providers.dart';
import 'blueprint_models.dart';
import 'blueprint_repository.dart';
import 'chapter_meta_models.dart';

/// v3 作品资料 / 章节资料依赖注入。
///
/// 数据全部来自后端：`ref.invalidate` 后重新拉取，不做本地权威缓存。

final blueprintRepositoryProvider = Provider<BlueprintRepository>(
  (ref) => BlueprintRepository(
    ref.watch(apiClientProvider),
    ref.watch(authorWorkRepositoryProvider),
    ref.watch(createRepositoryProvider),
  ),
);

/// 按会话编号读取待确认资料（确认前的人物档案等只读场景）。
final blueprintSessionProvider =
    FutureProvider.autoDispose.family<BlueprintSession, int>(
  (ref, sessionId) => ref.watch(blueprintRepositoryProvider).session(sessionId),
);

/// 作品资料会话（作品已确认的资料；作品没有会话时为 null）。
final workBlueprintSessionProvider =
    FutureProvider.autoDispose.family<BlueprintSession?, int>(
  (ref, workId) =>
      ref.watch(blueprintRepositoryProvider).workSession(workId),
);

/// 作品资料视图（结构化资料 + 台账改动合并），资料页与人物档案页共用。
///
/// 台账只是资料的一份投影：读取失败时按空台账继续，资料页仍能展示已确认的设计。
final workBlueprintProvider =
    FutureProvider.autoDispose.family<StoryBlueprint, int>((ref, workId) async {
  final repo = ref.watch(blueprintRepositoryProvider);
  final detail = await ref.watch(authorWorkDetailProvider(workId).future);
  WorkLedger ledger;
  try {
    ledger = await ref.watch(workLedgerProvider(workId).future);
  } catch (_) {
    ledger = const WorkLedger();
  }
  return repo.loadBlueprint(workId, work: detail.work, ledger: ledger);
});

/// 作品创作台账（章节页 AI 参考范围「作品资料」取它）。
final workLedgerProvider =
    FutureProvider.autoDispose.family<WorkLedger, int>((ref, workId) =>
        ref.watch(blueprintRepositoryProvider).ledger(workId));

/// 作品全部章节资料。
final workChapterMetaProvider =
    FutureProvider.autoDispose.family<ChapterMetaTable, int>((ref, workId) =>
        ref.watch(blueprintRepositoryProvider).chapterMeta(workId));
