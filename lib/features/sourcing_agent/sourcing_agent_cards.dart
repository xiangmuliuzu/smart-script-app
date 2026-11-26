import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/friendly_error.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../bookstore/widgets/bookstore_widgets.dart';
import '../chat/data/chat_providers.dart';
import 'sourcing_agent_repository.dart';

/// 合并同一条智能体回复中的多张 `work_list` 卡片：
/// - 自动过滤空的检索过程卡片，避免刷屏；
/// - 按 `workId` 去重，同一本书只保留信息更完整的一张；
/// - 将所有推荐书籍合并为一张卡片，供单行横向滑动展示。
List<SourcingCard> mergeSourcingCards(List<SourcingCard> cards) {
  final mergedWorks = <int, Map<String, dynamic>>{};
  final nonIdWorks = <Map<String, dynamic>>[];
  final otherCards = <SourcingCard>[];
  var scanLimited = false;

  for (final card in cards) {
    if (card.type != 'work_list') {
      otherCards.add(card);
      continue;
    }
    if (card.payload['scanLimited'] == true) scanLimited = true;
    for (final work in sourcingRows(card.payload['works'])) {
      final id = sourcingInt(work['workId']);
      if (id <= 0) {
        nonIdWorks.add(work);
        continue;
      }
      final existing = mergedWorks[id];
      if (existing == null) {
        mergedWorks[id] = Map<String, dynamic>.from(work);
      } else {
        mergedWorks[id] = _mergeWorkFields(existing, work);
      }
    }
  }

  final allWorks = [...mergedWorks.values, ...nonIdWorks];
  return [
    if (allWorks.isNotEmpty)
      SourcingCard('work_list', {
        'works': allWorks,
        if (scanLimited) 'scanLimited': true,
      }),
    ...otherCards,
  ];
}

Map<String, dynamic> _mergeWorkFields(
  Map<String, dynamic> base,
  Map<String, dynamic> incoming,
) {
  final merged = Map<String, dynamic>.from(base);
  for (final entry in incoming.entries) {
    final current = merged[entry.key];
    final next = entry.value;
    if (current == null ||
        (current is String && current.trim().isEmpty) ||
        (current is List && current.isEmpty)) {
      merged[entry.key] = next;
    }
  }
  return merged;
}

class SourcingCardView extends StatelessWidget {
  const SourcingCardView({super.key, required this.card});

  final SourcingCard card;

  @override
  Widget build(BuildContext context) {
    return switch (card.type) {
      'work_list' => _WorkCarouselSection(payload: card.payload),
      'work_comparison' => _WorkComparisonCard(payload: card.payload),
      'demand_brief' => _DemandCard(brief: card.payload),
      _ => const SizedBox.shrink(),
    };
  }
}

/// 智能体返回的推荐书籍：同一行横向滑动切换，每本书带封面与书籍信息，点击直达详情主页。
class _WorkCarouselSection extends StatelessWidget {
  const _WorkCarouselSection({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final works = sourcingRows(payload['works']);
    if (works.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 13,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '作品推荐',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const SizedBox(width: 6),
              _MetaPill(
                label: '共 ${works.length} 部',
                foreground: AppColors.text2,
                background: AppColors.fill,
              ),
              const Spacer(),
              if (works.length > 1)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '左右滑动',
                      style: TextStyle(fontSize: 11, color: AppColors.text3),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: AppColors.text3,
                    ),
                  ],
                ),
            ],
          ),
        ),
        SizedBox(
          height: 184,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            itemCount: works.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) => SizedBox(
              width: works.length == 1 ? 304 : 268,
              child: _WorkBookCard(work: works[index]),
            ),
          ),
        ),
      ],
    );
  }
}

/// 单本推荐书籍卡片：左侧封面 + 右侧书籍信息，点击整卡直接跳转作品详情主页。
class _WorkBookCard extends StatelessWidget {
  const _WorkBookCard({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final id = sourcingInt(work['workId']);
    final title = _text(work['title'], '作品待确认');
    final cover = _text(work['cover']);
    final author = _text(work['authorName'], '作者待确认');
    final tags = _strings(work['tags']).take(2).toList();
    final reason = _text(work['recommendationReason']);
    final summary = _text(work['summary']);
    final description = summary.isNotEmpty ? summary : reason;
    final canInquire = id > 0 && work['canInquire'] == true;

    final metaParts = <String>[
      author,
      _episodes(work),
      if (work['rating'] is num && (work['rating'] as num) > 0)
        '${(work['rating'] as num).toStringAsFixed(1)}分',
    ];

    void openDetail() {
      if (id > 0) context.push(RoutePath.workDetailUrl(id));
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        border: Border.all(color: AppColors.divider.withOpacity(0.75)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: id > 0 ? openDetail : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 11, 11, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.rSmall),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: WorkCover(
                          url: cover,
                          title: title,
                          width: 66,
                          height: 90,
                          radius: AppRadius.rSmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text1,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _priceLabel(work),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _isFree(work)
                                        ? AppColors.success
                                        : AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              metaParts.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.text3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 20,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _MetaPill(
                                    label: _copyright(work),
                                    foreground:
                                        work['copyrightRegistrationStatus'] ==
                                                'registered'
                                            ? AppColors.success
                                            : AppColors.text2,
                                    background:
                                        work['copyrightRegistrationStatus'] ==
                                                'registered'
                                            ? AppColors.success
                                                .withOpacity(0.10)
                                            : AppColors.warmGray,
                                  ),
                                  if (work['budgetMatch'] == true) ...[
                                    const SizedBox(width: 4),
                                    const _MetaPill(
                                      label: '预算内',
                                      foreground: AppColors.text1,
                                      background: AppColors.primaryTint,
                                    ),
                                  ],
                                  for (final tag in tags) ...[
                                    const SizedBox(width: 4),
                                    _MetaPill(
                                      label: tag,
                                      foreground: AppColors.text2,
                                      background: AppColors.fill,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Expanded(
                                child: Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.text2,
                                    height: 1.38,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(
                height: 1,
                thickness: 0.5,
                color: AppColors.divider.withOpacity(0.8),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                child: Row(
                  children: [
                    const Icon(
                      Icons.menu_book_outlined,
                      size: 13.5,
                      color: AppColors.text3,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '查看书籍详情',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: AppColors.text3,
                    ),
                    const Spacer(),
                    if (canInquire)
                      OutlinedButton(
                        onPressed: () => context.push(
                          Uri(
                            path: RoutePath.inquiryCreate,
                            queryParameters: {
                              'workId': '$id',
                              'title': title,
                            },
                          ).toString(),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppColors.primary),
                          foregroundColor: AppColors.text1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('发起询盘'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 多作品对比卡片：表头带迷你封面且可点击进入书籍详情。
class _WorkComparisonCard extends StatelessWidget {
  const _WorkComparisonCard({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final works = sourcingRows(payload['works']);
    final criterion = _text(payload['criteria']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        border: Border.all(color: AppColors.divider.withOpacity(0.7)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCaption(
            title: '作品对比',
            badge: works.isNotEmpty ? '${works.length} 部候选' : null,
            subtitle: criterion,
          ),
          const SizedBox(height: 10),
          if (works.isEmpty)
            const Text(
              '暂无可对比的作品。',
              style: TextStyle(fontSize: 13, color: AppColors.text2),
            )
          else
            _comparisonTable(context, works),
        ],
      ),
    );
  }

  Widget _comparisonTable(
    BuildContext context,
    List<Map<String, dynamic>> works,
  ) {
    final rows = <(String, String Function(Map<String, dynamic>))>[
      (
        '作者 / 题材',
        (work) => [_text(work['authorName']), _tags(work['tags'])]
            .where((value) => value.isNotEmpty)
            .join(' · ')
      ),
      ('参考价', _budget),
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
              '独家${_text(work['exclusiveStatus'], '待核实')}',
            ].join(' · ')
      ),
      ('商业化看点', (work) => _text(work['commercialHighlights'], '待评估')),
      ('风险提示', (work) => _text(work['riskNotes'], '待核实')),
    ];

    Widget cell(Widget child, {Color? bg}) => Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: child,
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.rSmall),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const FixedColumnWidth(156),
          columnWidths: const {0: FixedColumnWidth(84)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.all(color: AppColors.divider, width: 0.7),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: AppColors.fill),
              children: [
                cell(
                  const Text(
                    '对比维度',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text2,
                    ),
                  ),
                ),
                for (final work in works)
                  cell(_ComparisonWorkHeader(work: work)),
              ],
            ),
            for (final (label, content) in rows)
              TableRow(
                children: [
                  cell(
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                    bg: AppColors.warmGray.withOpacity(0.55),
                  ),
                  for (final work in works)
                    cell(
                      Text(
                        content(work).isEmpty ? '—' : content(work),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text1,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            TableRow(
              children: [
                cell(
                  const Text(
                    '操作',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                    ),
                  ),
                  bg: AppColors.warmGray.withOpacity(0.55),
                ),
                for (final work in works) cell(_WorkActions(work: work)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonWorkHeader extends StatelessWidget {
  const _ComparisonWorkHeader({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final id = sourcingInt(work['workId']);
    final title = _text(work['title'], '作品待确认');
    final cover = _text(work['cover']);

    return InkWell(
      onTap: id > 0 ? () => context.push(RoutePath.workDetailUrl(id)) : null,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          WorkCover(
            url: cover,
            title: title,
            width: 32,
            height: 44,
            radius: 5,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
                height: 1.3,
              ),
            ),
          ),
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
      runSpacing: 6,
      children: [
        TextButton(
          onPressed:
              id > 0 ? () => context.push(RoutePath.workDetailUrl(id)) : null,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: AppColors.fill,
            foregroundColor: AppColors.text1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          child: const Text('查看详情'),
        ),
        if (work['canInquire'] == true)
          OutlinedButton(
            onPressed: id > 0
                ? () => context.push(Uri(
                      path: RoutePath.inquiryCreate,
                      queryParameters: {
                        'workId': '$id',
                        'title': _text(work['title']),
                      },
                    ).toString())
                : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: AppColors.primary),
              foregroundColor: AppColors.text1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
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
    final checklist = _strings(brief['deliveryChecklist']).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        border: Border.all(color: AppColors.divider.withOpacity(0.7)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionCaption(title: '采购需求草案'),
          const SizedBox(height: 8),
          Text(
            _text(brief['title']),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warmGray,
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _briefFacts(brief))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '商业化诉求：${_text(brief['commercialGoal'])}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.text1,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '详细要求：${_text(brief['requirement'])}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
          if (checklist.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '交付验收清单',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 4),
            for (final item in checklist)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• $item',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.text2,
                    height: 1.45,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                onPressed: _copy,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  side: const BorderSide(color: AppColors.divider),
                  foregroundColor: AppColors.text1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.rSmall),
                  ),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text('复制需求单'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _sent || _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.rSmall),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(_sent
                      ? '已发给平台运营'
                      : _sending
                          ? '正在发送…'
                          : '发给平台运营立项'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption({
    required this.title,
    this.badge,
    this.subtitle = '',
  });

  final String title;
  final String? badge;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              _MetaPill(
                label: badge!,
                foreground: AppColors.text2,
                background: AppColors.fill,
              ),
            ],
          ],
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.text3),
          ),
        ],
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: foreground,
          height: 1.2,
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
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

String _oneLine(String value) => value.replaceAll(RegExp(r'\s+'), ' ');

Iterable<String> _strings(dynamic value) =>
    value is List ? value.whereType<String>() : const [];

String _tags(dynamic value) => _strings(value).join(' · ');

String _unit(dynamic value, String unit) =>
    value is num ? '$value $unit' : '待确认';

String _episodes(Map<String, dynamic> work) => _unit(work['episodeCount'], '集');

String _yuan(dynamic value) => value is num ? '¥$value' : '待确认';

bool _isFree(Map<String, dynamic> work) {
  final price = work['price'];
  return price is num && price <= 0;
}

String _priceLabel(Map<String, dynamic> work) {
  final price = work['price'];
  if (price is num) {
    if (price <= 0) return '免费';
    return '¥${price == price.truncateToDouble() ? price.toInt() : price}';
  }
  return '议价';
}

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
