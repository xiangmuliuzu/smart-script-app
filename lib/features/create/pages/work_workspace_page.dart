import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../data/author_work_models.dart';
import '../data/author_work_providers.dart';
import '../widgets/work_chapter_tab.dart';
import '../widgets/work_publish_tab.dart';
import '../widgets/work_settings_tab.dart';

/// 作品工作台（写作范式：章节 / 设置 / 发布 三 Tab）。
///
/// 单一数据源为 [authorWorkDetailProvider]（A 套作品详情，含章节与最近审核）；
/// 默认落在「章节」Tab，符合「作品=章节集合」的写作心智。
///
/// 批次边界：本批次完成骨架——章节列表展示（增删改与全屏编辑器在批次 2）、
/// 设置 Tab 的标题/分类/简介编辑（封面与定价在批次 3）、
/// 发布 Tab 的状态与审核信息展示（提交审核在批次 3）。
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(authorWorkDetailProvider(widget.workId));
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
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
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(AuthorWorkDetail detail) {
    return Column(
      children: [
        _WorkHeader(work: detail.work, chapterCount: detail.chapters.length),
        Material(
          color: AppColors.card,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.text2,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: '章节'),
              Tab(text: '设置'),
              Tab(text: '发布'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              WorkChapterTab(
                workId: widget.workId,
                chapters: detail.chapters,
                editable: detail.work.editable,
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

/// 顶部作品卡：封面缩略图 + 标题 + 状态徽标 + 分类 / 字数 / 章节数。
class _WorkHeader extends StatelessWidget {
  const _WorkHeader({required this.work, required this.chapterCount});

  final AuthorWorkItem work;
  final int chapterCount;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (work.genreName != null && work.genreName!.isNotEmpty) work.genreName!,
      '${work.wordCount} 字',
      '$chapterCount 章',
    ].join(' · ');
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkCover(url: work.cover ?? ''),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: work.status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  meta,
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'draft' => AppColors.text3,
      'reviewing' => AppColors.warning,
      'published' => AppColors.success,
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
        workStatusLabel(status),
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }
}