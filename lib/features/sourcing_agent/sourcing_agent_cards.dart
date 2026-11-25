import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/friendly_error.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../chat/data/chat_providers.dart';
import 'sourcing_agent_repository.dart';

class SourcingCardView extends StatelessWidget {
  const SourcingCardView({super.key, required this.card});

  final SourcingCard card;

  @override
  Widget build(BuildContext context) {
    return switch (card.type) {
      'work_list' || 'work_comparison' => _WorksCard(
          payload: card.payload,
          comparison: card.type == 'work_comparison',
        ),
      'demand_brief' => _DemandCard(brief: card.payload),
      _ => const SizedBox.shrink(),
    };
  }
}

class _WorksCard extends StatelessWidget {
  const _WorksCard({required this.payload, required this.comparison});

  final Map<String, dynamic> payload;
  final bool comparison;

  @override
  Widget build(BuildContext context) {
    final works = sourcingRows(payload['works']);
    final criterion = _text(payload['criteria']);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(comparison ? '作品对比' : '作品推荐',
                style: Theme.of(context).textTheme.titleMedium),
            if (criterion.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(criterion, style: const TextStyle(color: AppColors.text2)),
            ],
            if (payload['scanLimited'] == true)
              const Text('已达本次检索范围，可缩小条件后重试。'),
            const SizedBox(height: 8),
            if (works.isEmpty)
              const Text('本次检索未找到符合条件的作品。')
            else if (comparison)
              _comparison(works)
            else
              for (final work in works) _WorkRow(work: work),
          ],
        ),
      ),
    );
  }

  Widget _comparison(List<Map<String, dynamic>> works) {
    final rows = <(String, String Function(Map<String, dynamic>))>[
      (
        '作者和题材',
        (work) => [_text(work['authorName']), _tags(work['tags'])]
            .where((value) => value.isNotEmpty)
            .join(' · ')
      ),
      ('参考价与预算', _budget),
      (
        '集数 / 字数',
        (work) => '${_episodes(work)} / ${_unit(work['wordCount'], '字')}'
      ),
      (
        '版权状态',
        (work) => [
              _copyright(work),
              if (_text(work['copyrightCertNo']).isNotEmpty)
                _text(work['copyrightCertNo']),
              '独家状态${_text(work['exclusiveStatus'], '待核实')}',
            ].join(' · ')
      ),
      ('商业化看点', (work) => _text(work['commercialHighlights'], '待评估')),
      ('风险提示', (work) => _text(work['riskNotes'], '待核实')),
    ];
    Widget cell(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: child,
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(150),
        columnWidths: const {0: FixedColumnWidth(90)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder.all(color: AppColors.divider),
        children: [
          TableRow(children: [
            cell(const Text('对比维度')),
            for (final work in works) cell(Text(_text(work['title'], '作品待确认'))),
          ]),
          for (final (label, content) in rows)
            TableRow(children: [
              cell(Text(label)),
              for (final work in works) cell(Text(content(work))),
            ]),
          TableRow(children: [
            cell(const Text('操作')),
            for (final work in works) cell(_WorkActions(work: work)),
          ]),
        ],
      ),
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final tags = _tags(work['tags']);
    final reason = _text(work['recommendationReason']);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_text(work['title'], '作品待确认'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
              '${_text(work['authorName'], '作者待确认')} · ${_episodes(work)} · ${_budget(work)}'),
          Text(_copyright(work),
              style: const TextStyle(color: AppColors.text2)),
          if (tags.isNotEmpty) Text(tags),
          if (reason.isNotEmpty) Text(reason),
          if (_text(work['summary']).isNotEmpty) Text(_text(work['summary'])),
          _WorkActions(work: work),
        ],
      ),
    );
  }
}

class _WorkActions extends StatelessWidget {
  const _WorkActions({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final id = sourcingInt(work['workId']);
    return Wrap(
      spacing: 6,
      children: [
        TextButton(
          onPressed:
              id > 0 ? () => context.push(RoutePath.workDetailUrl(id)) : null,
          child: const Text('查看 · 试读'),
        ),
        OutlinedButton(
          onPressed: id > 0 && work['canInquire'] == true
              ? () => context.push(Uri(
                    path: RoutePath.inquiryCreate,
                    queryParameters: {
                      'workId': '$id',
                      'title': _text(work['title'])
                    },
                  ).toString())
              : null,
          child: const Text('发起询盘'),
        ),
      ],
    );
  }
}

class _DemandCard extends ConsumerStatefulWidget {
  const _DemandCard({required this.brief});

  final Map<String, dynamic> brief;

  @override
  ConsumerState<_DemandCard> createState() => _DemandCardState();
}

class _DemandCardState extends ConsumerState<_DemandCard> {
  bool _sending = false;
  bool _sent = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
          ClipboardData(text: formatSourcingBrief(widget.brief)));
      if (mounted) _notice('采购需求已复制');
    } catch (_) {
      if (mounted) _notice('暂时无法复制采购需求');
    }
  }

  Future<void> _send() async {
    if (_sending || _sent) return;
    setState(() => _sending = true);
    try {
      final repository = ref.read(chatRepositoryProvider);
      final session = await repository.createAdminSession(
        businessType: 'GENERAL',
        businessName: '平台沟通',
      );
      await repository.sendMessage(
          session.session.sessionId, formatSourcingBrief(widget.brief));
      if (!mounted) return;
      setState(() => _sent = true);
      _notice('采购需求已发给平台运营');
      context.push(RoutePath.chatDetail(session.session.sessionId));
    } catch (error) {
      if (mounted) _notice(FriendlyError.message(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final brief = widget.brief;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('采购需求草案', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_text(brief['title']),
                style: Theme.of(context).textTheme.titleSmall),
            for (final line in _briefFacts(brief)) Text(line),
            const SizedBox(height: 8),
            Text('商业化诉求：${_text(brief['commercialGoal'])}'),
            Text('详细要求：${_text(brief['requirement'])}'),
            const SizedBox(height: 8),
            const Text('交付验收清单'),
            for (final item in _strings(brief['deliveryChecklist']))
              Text('• $item'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                OutlinedButton(onPressed: _copy, child: const Text('复制需求单')),
                FilledButton(
                  onPressed: _sent || _sending ? null : _send,
                  child: Text(_sent
                      ? '已发给平台运营'
                      : _sending
                          ? '正在发送…'
                          : '发给平台运营立项'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String formatSourcingBrief(Map<String, dynamic> brief) => [
      '# 采购需求草案｜${_oneLine(_text(brief['title']))}',
      '',
      for (final line in _briefFacts(brief)) '- $line',
      '',
      '## 商业化诉求',
      _text(brief['commercialGoal']),
      '',
      '## 详细要求',
      _text(brief['requirement']),
      '',
      '## 交付验收清单',
      for (final item in _strings(brief['deliveryChecklist']))
        '- ${_oneLine(item)}',
    ].join('\n');

List<String> _briefFacts(Map<String, dynamic> brief) => [
      '任务类型：${switch (brief['taskType']) {
        'script' => '剧本',
        'script_storyboard' => '剧本 + 分镜',
        'storyboard' => '分镜',
        _ => '待确认',
      }}',
      '题材标签：${_strings(brief['genreTags']).join('、')}',
      '目标集数：${_unit(brief['totalEpisodes'], '集')}',
      '预算参考：${_yuan(brief['budgetYuan'])}',
      '期望周期：${_unit(brief['durationDays'], '天')}',
    ];

String _text(dynamic value, [String fallback = '']) =>
    value is String && value.trim().isNotEmpty ? value : fallback;

String _oneLine(String value) => value.replaceAll(RegExp(r'\s+'), ' ');

Iterable<String> _strings(dynamic value) =>
    value is List ? value.whereType<String>() : const [];
String _tags(dynamic value) => _strings(value).join(' · ');
String _unit(dynamic value, String unit) =>
    value is num ? '$value $unit' : '待确认';
String _episodes(Map<String, dynamic> work) => _unit(work['episodeCount'], '集');
String _yuan(dynamic value) => value is num ? '¥$value' : '待确认';

String _budget(Map<String, dynamic> work) {
  final price = _yuan(work['price']);
  return switch (work['budgetMatch']) {
    true => '$price · 预算内',
    false => '$price · 超出预算',
    _ => price,
  };
}

String _copyright(Map<String, dynamic> work) =>
    switch (work['copyrightRegistrationStatus']) {
      'registered' => '版权已登记',
      'unregistered' => '版权未登记',
      _ => '登记状态待确认',
    };
