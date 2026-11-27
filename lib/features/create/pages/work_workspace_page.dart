import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../ai/ai_quota_dialog.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../../welfare/data/welfare_providers.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';
import '../data/blueprint_providers.dart';
import '../data/chapter_meta_models.dart';
import '../widgets/work_chapter_tab.dart';
import '../widgets/work_publish_tab.dart';
import '../widgets/work_settings_tab.dart';
import '../widgets/work_storyboard_tab.dart';

/// 作品工作台（v3）。
///
/// - 顶部作品卡：封面 + 标题 + 状态 + 字数 / 章节数，并提供「作品资料」「设置」入口；
/// - 章节 Tab：按章展示进度（概要已定 / 待定概要 / 已写 X 字），点章进入创作页；
///   新建章节统一走底部「＋ 新建章节」：优先让 AI 依据作品资料生成本章概要后落库
///   （显式递增 chapterNo），积分不足或 AI 失败时降级为空白章节，不阻断手工写作；
/// - 保留「分镜 / 设置 / 发布（含版本管理）」等原有能力。
///
/// 单一数据源：A 套 `GET /users/me/works/{workId}` + `chapter-meta`；
/// 章节资料在章节页维护，工作台只读取展示状态。
class WorkWorkspacePage extends ConsumerStatefulWidget {
  const WorkWorkspacePage({super.key, required this.workId, this.title});

  final int workId;

  /// 列表页透传的标题，用于详情加载完成前的 AppBar 占位。
  final String? title;

  @override
  ConsumerState<WorkWorkspacePage> createState() => _WorkWorkspacePageState();
}

class _WorkWorkspacePageState extends ConsumerState<WorkWorkspacePage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  bool _creatingChapter = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 「＋ 新建章节」：优先 AI 起草本章概要；AI 不可用（积分不足 / 失败）时
  /// 降级为空白章节，保证无积分作者也能继续手工写作；显式传递增 chapterNo。
  Future<void> _newChapter(AuthorWorkDetail detail) async {
    if (_creatingChapter) return;
    if (!detail.work.editable) {
      showAppToast(context, '作品审核中或没有编辑权限，暂不能新建章节');
      return;
    }
    var nextNo = 1;
    for (final chapter in detail.chapters) {
      if (chapter.chapterNo >= nextNo) nextNo = chapter.chapterNo + 1;
    }
    final quota = ref.read(welfareAssetProvider).valueOrNull;
    // 积分不足：先说明再降级建空白章（不弹「去赚积分」拦路弹窗，避免封死建章）。
    final noQuota = quota != null && quota.points.balance == 0;
    if (noQuota) {
      showAppToast(context, '积分不足，本次新建空白章节，可稍后用 AI 起草概要');
    }
    setState(() => _creatingChapter = true);
    final repo = ref.read(blueprintRepositoryProvider);
    ChapterDraftResult? draft;
    if (!noQuota) {
      try {
        draft = await repo.draftChapter(
          workId: widget.workId,
          chapterNo: nextNo,
        );
      } on ApiException catch (e) {
        if (!mounted) return;
        if (isQuotaInsufficientError(e)) {
          showAppToast(context, '积分不足，本次新建空白章节，可稍后用 AI 起草概要');
        } else {
          showAppToast(context, 'AI 生成失败，将新建空白章节。${e.message}');
        }
      } catch (_) {
        if (mounted) showAppToast(context, 'AI 生成失败，将新建空白章节');
      }
    }
    if (!mounted) return;
    final title = draft?.title.trim().isNotEmpty == true
        ? draft!.title.trim()
        : '第 $nextNo 章';
    final summary = draft?.summary ?? '';
    try {
      final chapterId = await ref.read(authorWorkRepositoryProvider).addChapter(
            widget.workId,
            chapterNo: nextNo,
            chapterTitle: title.length > 100 ? title.substring(0, 100) : title,
            summary: summary,
          );
      if (draft != null && !draft.meta.isEmpty) {
        try {
          await repo.saveChapterMeta(widget.workId, nextNo, draft.meta);
        } catch (_) {
          // 本章资料保存失败不影响章节本身，可在章节页「AI 整理」重试。
        }
      }
      ref.invalidate(authorWorkDetailProvider(widget.workId));
      ref.invalidate(workChapterMetaProvider(widget.workId));
      ref.invalidate(welfareAssetProvider);
      if (!mounted) return;
      showAppToast(context, draft?.hasDraft == true
          ? '第 $nextNo 章概要已生成，可继续创作'
          : '已新建第 $nextNo 章，可手动填写概要');
      await context.push(RoutePath.chapterWriteUrl(
        workId: widget.workId,
        chapterId: chapterId,
      ));
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, '新建章节失败：${e.message}');
    } catch (_) {
      if (mounted) showAppToast(context, '新建章节失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _creatingChapter = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 预先订阅一次积分：新建章节时要即时判断「积分不足 → 降级空白章」，
    // 只在点击时 ref.read 会拿到首次的 loading 态。
    ref.watch(welfareAssetProvider);
    final detailAsync = ref.watch(authorWorkDetailProvider(widget.workId));
    final metas = ref.watch(workChapterMetaProvider(widget.workId)).valueOrNull ??
        ChapterMetaTable.empty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(detailAsync.valueOrNull?.work.title.isNotEmpty == true
            ? detailAsync.value!.work.title
            : (widget.title?.isNotEmpty == true ? widget.title! : '作品工作台')),
      ),
      body: detailAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(authorWorkDetailProvider(widget.workId)),
        ),
        data: (detail) => _buildBody(detail, metas),
      ),
    );
  }

  Widget _buildBody(AuthorWorkDetail detail, ChapterMetaTable metas) {
    return Column(
      children: [
        _WorkHeader(
          work: detail.work,
          shelfStatus: detail.shelfStatus,
          chapterCount: detail.chapters.length,
          onOpenBlueprint: () => context.push(RoutePath.aiBlueprintUrl(
            workId: widget.workId,
            title: detail.work.title,
          )),
          onOpenSettings: () => _tabController.animateTo(2),
        ),
        Material(
          color: AppColors.card,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.text1,
            unselectedLabelColor: AppColors.text2,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: '章节'),
              Tab(text: '分镜'),
              Tab(text: '设置'),
              Tab(text: '发布'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ChaptersPanel(
                workId: widget.workId,
                detail: detail,
                metas: metas,
                creating: _creatingChapter,
                onNewChapter: () => _newChapter(detail),
              ),
              WorkStoryboardTab(
                workId: widget.workId,
                editable: detail.work.editable,
                hasChapters: detail.chapters.isNotEmpty,
              ),
              WorkSettingsTab(detail: detail),
              WorkPublishTab(workId: widget.workId, detail: detail),
            ],
          ),
        ),
      ],
    );
  }
}

/// 章节面板：章节列表 + 唯一的「＋ 新建章节」入口 + 底部说明。
///
/// 新建章节只保留底部整宽按钮这一个入口（取消右下角 FAB，避免与底部按钮重复、
/// 遮住最后一条章节）。按钮固定在面板底部，空目录时同样可见。
class _ChaptersPanel extends StatelessWidget {
  const _ChaptersPanel({
    required this.workId,
    required this.detail,
    required this.metas,
    required this.creating,
    required this.onNewChapter,
  });

  final int workId;
  final AuthorWorkDetail detail;
  final ChapterMetaTable metas;
  final bool creating;
  final VoidCallback onNewChapter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: WorkChapterTab(
            workId: workId,
            chapters: detail.chapters,
            editable: detail.work.editable,
            metas: metas,
          ),
        ),
        Container(
          color: AppColors.card,
          padding: EdgeInsets.fromLTRB(
              16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (detail.chapters.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '分镜和本章资料跟着章节走，不再和章节平级。',
                    style: TextStyle(fontSize: 11.5, color: AppColors.text3),
                  ),
                ),
              if (detail.work.editable)
                FilledButton.icon(
                  onPressed: creating ? null : onNewChapter,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(creating ? '正在生成…' : '新建章节'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部作品卡：封面 + 标题 + 状态徽标 + 字数 / 章节数 + 资料 / 设置入口。
class _WorkHeader extends StatelessWidget {
  const _WorkHeader({
    required this.work,
    required this.shelfStatus,
    required this.chapterCount,
    required this.onOpenBlueprint,
    required this.onOpenSettings,
  });

  final AuthorWorkItem work;
  final String? shelfStatus;
  final int chapterCount;
  final VoidCallback onOpenBlueprint;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      '${work.wordCount} 字',
      '$chapterCount 章',
      if (work.updateTime != null && work.updateTime!.isNotEmpty)
        '更新于 ${_shortDate(work.updateTime!)}',
    ].join(' · ');
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkCover(url: work.cover ?? '', title: work.title, width: 86, height: 120),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        work.title.isEmpty ? '未命名作品' : work.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(
                        status: work.status,
                        shelfStatus: shelfStatus ?? work.shelfStatus),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _HeaderButton(
                        label: '作品资料', onTap: onOpenBlueprint),
                    const SizedBox(width: 8),
                    _HeaderButton(label: '设置', onTap: onOpenSettings),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortDate(String raw) {
    final text = raw.trim();
    if (text.length >= 16) return text.substring(5, 16);
    return text;
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.text2)),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.shelfStatus = ''});

  final String status;
  final String shelfStatus;

  @override
  Widget build(BuildContext context) {
    final onShelf = status == 'published' && shelfStatus == 'on_shelf';
    final label =
        status == 'published' ? (onShelf ? '已上架' : '审核通过，待上架') : workStatusLabel(status);
    final color = switch (status) {
      'draft' => AppColors.text3,
      'reviewing' => AppColors.warning,
      'published' => onShelf ? AppColors.success : AppColors.warning,
      'revision' || 'rejected' => AppColors.danger,
      _ => AppColors.text3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }
}
