import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';
import '../../user_center/widgets/user_center_scaffold.dart';

/// 通知偏好（规格 §8.6，契约 §1.5）。
///
/// 按具体业务控制站内消息；保存时只提交改动项。
class NotificationPreferencePage extends ConsumerStatefulWidget {
  const NotificationPreferencePage({super.key});

  @override
  ConsumerState<NotificationPreferencePage> createState() => _NotificationPreferencePageState();
}

class _NotificationPreferencePageState extends ConsumerState<NotificationPreferencePage> {
  List<NotificationPreference>? _items;
  final Set<String> _dirty = {};
  bool _saving = false;
  String? _error;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPreferencesProvider);
    return UserCenterScaffold(
        title: '通知偏好',
        actions: null,
        body: async.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(notificationPreferencesProvider),
        ),
        data: (preferences) {
          if (!_loaded) {
            _loaded = true;
            _items = List.of(preferences);
          }
          return _buildBody();
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: (_saving || _dirty.isEmpty) ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final items = _items ?? const <NotificationPreference>[];
    if (items.isEmpty) {
      return const EmptyView(message: '暂无可配置的通知类型');
    }
    final hasTradeCategories = items.any((item) =>
        item.channel == NotificationChannel.inbox && item.type == PreferenceType.inquiry);
    final visible = items.where((item) =>
        item.channel == NotificationChannel.inbox &&
        item.type != null && (item.type != PreferenceType.transaction || !hasTradeCategories)).toList();
    if (visible.isEmpty) return const EmptyView(message: '暂无可配置的通知类型');
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _buildChannel(NotificationChannel.inbox, visible),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            '关闭后不再接收该类站内通知，已有消息保留。平台公告关闭期间暂不显示，重新开启后可再次查看。',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildChannel(NotificationChannel channel, List<NotificationPreference> items) {
    final channelItems = items.where((e) => e.channel == channel).toList();
    if (channelItems.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            channel.label,
            style: const TextStyle(fontSize: 13, color: AppColors.text3),
          ),
        ),
        Container(
          color: AppColors.card,
          child: Column(
            children: [
              for (final item in channelItems)
                SwitchListTile(
                  value: item.enabled,
                  title: Text(item.typeLabel),
                  subtitle: Text(_description(item.type!)),
                  activeColor: AppColors.primary,
                  onChanged: _saving ? null : (value) => _toggle(item, channel, value),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  String _description(PreferenceType type) => switch (type) {
        PreferenceType.inquiry => '新询盘、询盘被接受',
        PreferenceType.order => '订单生成、付款、完成及取消',
        PreferenceType.contract => '合同签署和签署完成',
        PreferenceType.system => '平台消息和公告',
        PreferenceType.review => '实名和创作者申请审核结果',
        PreferenceType.benefit => '福利相关消息',
        PreferenceType.transaction => '询盘、订单及合同通知',
      };

  /// 本地先改状态，保存时只提交改动项。
  void _toggle(NotificationPreference item, NotificationChannel channel, bool value) {
    final items = _items;
    if (items == null) return;
    final key = '${channel.code}/${item.typeCode}';
    final index = items.indexWhere((e) => e.channel == channel && e.typeCode == item.typeCode);
    if (index < 0) return;
    setState(() {
      items[index] = items[index].copyWith(enabled: value);
      _dirty.add(key);
    });
  }

  Future<void> _save() async {
    final items = _items;
    if (items == null) return;
    final changed = items
        .where((e) => _dirty.contains('${e.channel.code}/${e.typeCode}'))
        .toList();
    if (changed.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(messageRepositoryProvider).updatePreferences(changed);
      _dirty.clear();
      ref.invalidate(notificationPreferencesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知偏好已保存')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '保存失败，请稍后重试');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error!)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
