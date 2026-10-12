import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/common_views.dart';
import '../bookstore/widgets/bookstore_widgets.dart';
import 'data/author_work_models.dart';
import 'data/author_work_providers.dart';

/// 创作入口（底部导航「创作」tab）。
///
/// 采用写作 App 书架范式：状态筛选 Tab + **三列网格**作品卡（序号 + 标题 + 分类 + 封面），
/// 三列排布使同屏作品数大幅提升，避免作品多时频繁上下滑动。
/// 右上角「新建」进入创建表单；点卡片进入作品工作台（章节 / 设置 / 发布）。
///
/// 数据走 A 套 /users/me/works（写作链路），状态由服务端按最新审核记录派生。
class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key});

  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  /// 状态筛选项（value 与 A 套 status 入参一致；all 表示不过滤）。
  static const List<({String value, String label})> _filters = [
    (value: 'all', label: '全部'),
    (value: 'draft', label: '草稿'),
    (value: 'reviewing', label: '审核中'),
    (value: 'revision', label: '待修改'),
    (value: 'rejected', label: '已驳回'),
    (value: 'published', label: '已发布'),
  ];

  /// 网格列数（复刻图二：固定三列）。
  static const int _columns = 3;

  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    final worksAsync = ref.watch(myWorksProvider(_status));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('我的作品'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(RoutePath.workUpload),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('新建'),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            filters: _filters,
            selected: _status,
            onChanged: (value) => setState(() => _status = value),
          ),
          Expanded(
            child: worksAsync.when(
              loading: () => const LoadingView(message: '加载中'),
              error: (error, _) => ErrorView(
                message: error is ApiException ? error.message : '加载失败，请稍后重试',
                onRetry: () => ref.invalidate(myWorksProvider(_status)),
              ),
              data: _buildGrid,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<AuthorWorkItem> works) {
    if (works.isEmpty) {
      return _EmptyWorks(onCreate: () => context.push(RoutePath.workUpload));
    }
    final cells = _columnMajor(works);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myWorksProvider(_status)),
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 10,
          childAspectRatio: 0.8,
        ),
        itemCount: cells.length,
        itemBuilder: (context, index) {
          final cell = cells[index];
          return _WorkCard(
            no: cell.no,
            work: cell.work,
            onTap: () => context.push(
              RoutePath.workWorkspaceUrl(
                workId: cell.work.workId,
                title: cell.work.title,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 按「列优先」重排：先自上而下填满第一列，再填第二列……
  ///
  /// GridView 默认「行优先」放置，这里预先按列优先顺序重排，再交给行优先网格渲染，
  /// 即可得到图二那种 01/02/03 竖排一列的视觉效果，同时保留 GridView 的懒加载。
  List<({int no, AuthorWorkItem work})> _columnMajor(List<AuthorWorkItem> works) {
    final rows = (works.length / _columns).ceil();
    final cells = <({int no, AuthorWorkItem work})>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < _columns; col++) {
        final origin = col * rows + row;
        if (origin < works.length) {
          cells.add((no: origin + 1, work: works[origin]));
        }
      }
    }
    return cells;
  }
}

/// 状态筛选条（横向可滚动标签）。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onChanged,
  });

  final List<({String value, String label})> filters;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filter.label),
                  selected: selected == filter.value,
                  onSelected: (_) => onChanged(filter.value),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: selected == filter.value
                        ? AppColors.primary
                        : AppColors.text2,
                  ),
                  selectedColor: AppColors.primaryTint,
                  backgroundColor: AppColors.card,
                  side: BorderSide(
                    color: selected == filter.value
                        ? AppColors.primary
                        : AppColors.divider,
                  ),
                  showCheckmark: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 网格作品卡（复刻图二）：左列「序号 + 标题 + 分类」，右侧封面缩略图。
class _WorkCard extends StatelessWidget {
  const _WorkCard({
    required this.no,
    required this.work,
    required this.onTap,
  });

  /// 作品序号（1 起，按列表原始顺序，与状态筛选无关）。
  final int no;
  final AuthorWorkItem work;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = work.title.isEmpty ? '未命名作品' : work.title;
    final genre = (work.genreName != null && work.genreName!.isNotEmpty)
        ? work.genreName!
        : '未分类';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.rSmall),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        no.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: AppColors.text1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    genre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.text3),
                  ),
                  const SizedBox(height: 5),
                  _StatusBadge(status: work.status),
                ],
              ),
            ),
            const SizedBox(width: 6),
            WorkCover(url: work.cover ?? '', width: 30, height: 42),
          ],
        ),
      ),
    );
  }
}

/// 状态角标（审核派生状态）：不同状态用语义色区分，便于一眼掌握作品进度。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'published' => AppColors.success,
      'reviewing' => AppColors.warning,
      'revision' => AppColors.warning,
      'rejected' => AppColors.danger,
      _ => AppColors.text3,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          workStatusLabel(status),
          style: TextStyle(fontSize: 10, color: color),
        ),
      ),
    );
  }
}

/// 空态：尚无作品时引导新建。
class _EmptyWorks extends StatelessWidget {
  const _EmptyWorks({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const EmptyView(message: '还没有作品，点击右下角开始创作', icon: Icons.menu_book_outlined),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: onCreate,
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }
}