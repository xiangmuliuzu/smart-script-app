import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/content_providers.dart';

const _lockedMessage = '该分镜暂未开放试读，请在取得授权后查看。';

String _title(Map<String, dynamic> item) =>
    (item['chapterTitle'] ?? item['title'] ?? '未命名分镜').toString();

String _accessLabel(Map<String, dynamic> item) {
  if (item['readable'] != true) return '暂未开放';
  return item['trialEnabled'] == true ? '可试读' : '可阅读';
}

/// 与章节目录同级。点击目录项进入新页面，正文不在目录里展开。
class WorkStoryboardPage extends ConsumerWidget {
  const WorkStoryboardPage({super.key, required this.workId, this.title});

  final int workId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = workStoryboardsProvider(workId);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title?.isNotEmpty == true ? '${title!} · 分镜目录' : '分镜目录'),
      ),
      body: ref.watch(provider).when(
            loading: () => const LoadingView(message: '正在加载分镜目录'),
            error: (error, __) => ErrorView(
              message: _errorMessage(error, '分镜目录加载失败，请重试'),
              onRetry: () => ref.invalidate(provider),
            ),
            data: (items) => items.isEmpty
                ? const EmptyView(
                    message: '暂无分镜内容',
                    icon: Icons.movie_filter_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final readable = item['readable'] == true;
                      final storyboardId =
                          int.tryParse(item['storyboardId'].toString());
                      final shotCount = item['shotCount'] ?? item['totalShots'];
                      return Card(
                        elevation: 0,
                        color: AppColors.card,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryTint,
                            child: Text('${index + 1}',
                                style:
                                    const TextStyle(color: AppColors.primary)),
                          ),
                          title: Text(_title(item)),
                          subtitle: Text([
                            if (shotCount != null) '$shotCount 个镜头',
                            _accessLabel(item),
                          ].join(' · ')),
                          trailing: Icon(readable
                              ? Icons.chevron_right
                              : Icons.lock_outline),
                          onTap: () {
                            if (!readable || storyboardId == null) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                    readable ? '分镜暂时无法打开' : _lockedMessage),
                              ));
                              return;
                            }
                            Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => StoryboardReadPage(
                                workId: workId,
                                storyboardId: storyboardId,
                                title: _title(item),
                              ),
                            ));
                          },
                        ),
                      );
                    },
                  ),
          ),
    );
  }
}

class StoryboardReadPage extends ConsumerWidget {
  const StoryboardReadPage({
    super.key,
    required this.workId,
    required this.storyboardId,
    required this.title,
  });

  final int workId;
  final int storyboardId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = workStoryboardsProvider(workId);
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(title: const Text('分镜阅读')),
      body: ref.watch(provider).when(
            skipLoadingOnRefresh: false,
            loading: () => const LoadingView(message: '正在加载分镜正文'),
            error: (error, __) => ErrorView(
              message: _errorMessage(error, '分镜正文加载失败，请重试'),
              onRetry: () => ref.invalidate(provider),
            ),
            data: (items) {
              Map<String, dynamic>? storyboard;
              for (final item in items) {
                if (item['storyboardId'].toString() ==
                    storyboardId.toString()) {
                  storyboard = item;
                  break;
                }
              }
              if (storyboard == null) {
                return const EmptyView(message: '该分镜已不在目录中');
              }
              if (storyboard['readable'] != true) {
                return const EmptyView(
                    message: _lockedMessage, icon: Icons.lock_outline);
              }
              final content = (storyboard['content'] ?? '').toString().trim();
              if (content.isEmpty) {
                return const EmptyView(message: '暂无分镜正文');
              }
              return SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title.isEmpty ? _title(storyboard) : title,
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text(_accessLabel(storyboard),
                              style: const TextStyle(color: AppColors.text3)),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 12),
                          SelectableText(content,
                              style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.8,
                                  color: AppColors.text1)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }
}

String _errorMessage(Object error, String fallback) {
  if (error is ApiException && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return fallback;
}
