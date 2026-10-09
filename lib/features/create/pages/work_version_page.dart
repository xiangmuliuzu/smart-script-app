import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/widgets/user_center_scaffold.dart';
import '../data/create_models.dart';
import '../data/create_providers.dart';

/// 版本管理（APP 页面14，接口 2.9.7 列表 + 2.9.8 新建 + 2.9.9 详情）。
///
/// 版本号按作品内自增，新建后成为当前版本；列表不含正文，点开才拉详情。
class WorkVersionPage extends ConsumerStatefulWidget {
  const WorkVersionPage({super.key, required this.workId, this.title});

  final int workId;
  final String? title;

  @override
  ConsumerState<WorkVersionPage> createState() => _WorkVersionPageState();
}

class _WorkVersionPageState extends ConsumerState<WorkVersionPage> {
  final _descCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _newVersion() async {
    _descCtrl.clear();
    _contentCtrl.clear();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '新建版本',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text1),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: '变更说明（可留空）'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contentCtrl,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: '版本内容（可留空）',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('提交'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _creating = true);
    try {
      await ref.read(createRepositoryProvider).createVersion(
            widget.workId,
            versionDesc: _descCtrl.text.trim(),
            content: _contentCtrl.text.trim(),
          );
      ref.invalidate(workVersionsProvider(widget.workId));
      if (!mounted) return;
      _toast('新版本已创建');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('创建版本失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final versionsAsync = ref.watch(workVersionsProvider(widget.workId));
    final title = widget.title;
    return UserCenterScaffold(
      title: (title == null || title.isEmpty) ? '版本管理' : '版本管理 · $title',
      actions: [
        TextButton(
          onPressed: _creating ? null : _newVersion,
          child: const Text('新建版本'),
        ),
      ],
      body: versionsAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(workVersionsProvider(widget.workId)),
        ),
        data: (versions) {
          if (versions.isEmpty) {
            return const EmptyView(message: '暂无版本记录', icon: Icons.history_outlined);
          }
          return ListView.separated(
            itemCount: versions.length,
            separatorBuilder: (_, __) => const Divider(height: 0.5, color: AppColors.divider),
            itemBuilder: (context, index) => _VersionTile(
              item: versions[index],
              onTap: () => context.push(
                RoutePath.workVersionDetailUrl(
                  versions[index].versionId,
                  title: 'V${versions[index].versionNo}',
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({required this.item, required this.onTap});

  final WorkVersionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'V${item.versionNo}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1,
                        ),
                      ),
                      if (item.isCurrentVersion) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '当前版本',
                            style: TextStyle(fontSize: 11, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (item.changeLog == null || item.changeLog!.isEmpty)
                        ? '无变更说明'
                        : item.changeLog!,
                    style: const TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.createTime ?? '时间未知',
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}