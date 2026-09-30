import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';
import '../widgets/bookstore_widgets.dart';

/// 作品详情（B 模块，接口 2.7.2 作品详情）。
///
/// 公开页，游客可读。未上架或已删除的作品后端按 404 拒绝，此处落到错误态。
class WorkDetailPage extends ConsumerWidget {
  const WorkDetailPage({super.key, required this.workId});

  final int workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(workDetailProvider(workId));
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('作品详情')),
      body: detailAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(workDetailProvider(workId)),
        ),
        data: (work) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(workDetailProvider(workId)),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Header(work: work),
              _ChapterEntry(work: work),
              if (work.summary.isNotEmpty)
                _Block(title: '作品简介', content: work.summary),
              if (work.coreSetting.isNotEmpty)
                _Block(title: '核心设置', content: work.coreSetting),
              if (work.characterSetting.isNotEmpty)
                _Block(title: '角色设定', content: work.characterSetting),
              _InfoBlock(work: work),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.work});

  final BookItem work;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WorkCover(url: work.cover, width: 96, height: 130, radius: AppRadius.r),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.title.isEmpty ? '未命名作品' : work.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      work.authorName.isEmpty ? '未知作者' : work.authorName,
                      style: const TextStyle(fontSize: 13, color: AppColors.text2),
                    ),
                    const SizedBox(height: 6),
                    if (work.genreName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          work.genreName,
                          style: const TextStyle(fontSize: 11, color: AppColors.primary),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      work.priceLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: work.isFree ? AppColors.success : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(label: '浏览', value: '${work.viewCount}'),
              _Stat(label: '收藏', value: '${work.favoriteCount}'),
              _Stat(label: '销量', value: '${work.saleCount}'),
              _Stat(label: '评分', value: work.rating.toStringAsFixed(1)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 章节目录入口（B 模块试读链路）。
class _ChapterEntry extends StatelessWidget {
  const _ChapterEntry({required this.work});

  final BookItem work;

  @override
  Widget build(BuildContext context) {
    final String subtitle = work.previewEnabled && work.previewEpisodes > 0
        ? '可试读前 ${work.previewEpisodes} 集'
        : '暂未开启试读';
    return Container(
      color: AppColors.card,
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => context.push(
          RoutePath.chapterListUrl(work.workId, title: work.title),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.menu_book_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                '章节目录',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.text3)),
        ],
      ),
    );
  }
}

/// 长文本区块（简介 / 核心设置 / 角色设定）。
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.text2),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.work});

  final BookItem work;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '作品信息',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 10),
          _row('作品类型', work.workType),
          _row('上传类型', work.uploadType),
          _row('篇幅类型', work.lengthType),
          _row('质量等级', work.qualityLevel),
          _row('字数', '${work.wordCount}'),
          _row('集数', '${work.episodeCount}'),
          _row('时长（分钟）', '${work.duration}'),
          _row('是否开启交易', work.tradeEnabled ? '是' : '否'),
          _row(
            '试读',
            work.previewEnabled ? '已开启，共 ${work.previewEpisodes} 集' : '未开启',
          ),
          _row('上架时间', work.createTime ?? '—'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 13, color: AppColors.text1),
              ),
            ),
          ],
        ),
      );
}