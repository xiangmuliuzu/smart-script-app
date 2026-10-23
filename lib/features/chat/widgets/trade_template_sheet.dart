import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../trade/data/trade_models.dart';
import '../../trade/data/trade_providers.dart';
import '../data/chat_models.dart';
import '../data/chat_providers.dart';

/// 交易会话定型文选择面板（底部弹出式）。
///
/// 按分类 Tab 展示定型文按钮，按当前用户角色过滤。
/// 含 `{price}` 的模板点击后展开内嵌金额输入行，发送时同步更新报价。
class TradeTemplateSheet extends ConsumerStatefulWidget {
  const TradeTemplateSheet({
    super.key,
    required this.sessionId,
    required this.inquiryId,
    required this.isBuyer,
    required this.isSeller,
    required this.licenseType,
    required this.onSent,
  });

  final int sessionId;
  final int inquiryId;
  final bool isBuyer;
  final bool isSeller;
  final String? licenseType;

  /// 发送成功后的回调（用于刷新消息列表、关闭面板等）。
  final VoidCallback onSent;

  /// 展示定型文选择面板。
  static Future<void> show(
    BuildContext context, {
    required int sessionId,
    required int inquiryId,
    required bool isBuyer,
    required bool isSeller,
    required String? licenseType,
    required VoidCallback onSent,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TradeTemplateSheet(
        sessionId: sessionId,
        inquiryId: inquiryId,
        isBuyer: isBuyer,
        isSeller: isSeller,
        licenseType: licenseType,
        onSent: onSent,
      ),
    );
  }

  @override
  ConsumerState<TradeTemplateSheet> createState() => _TradeTemplateSheetState();
}

class _TradeTemplateSheetState extends ConsumerState<TradeTemplateSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _expandedIndex = -1; // 展开价格输入的模板索引（在过滤后列表中的位置）
  final TextEditingController _priceController = TextEditingController();
  bool _isSending = false;

  /// 三个 Tab：价格协商（含价格 + 纯文字合并）、交易进展、通用沟通
  static const List<_TabInfo> _tabs = [
    _TabInfo(label: '💰 价格协商', categories: {'price_param', 'price_text'}),
    _TabInfo(label: '📋 交易进展', categories: {'progress'}),
    _TabInfo(label: '💬 通用沟通', categories: {'general'}),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      // 切换 Tab 时收起价格输入
      if (_expandedIndex != -1) {
        setState(() => _expandedIndex = -1);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(tradeTemplatesProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽手柄
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '选择消息',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          // Tab 栏
          TabBar(
            controller: _tabController,
            tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.text3,
            indicatorColor: AppColors.primary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Divider(height: 1),
          // Tab 内容
          Flexible(
            child: templatesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (templates) => TabBarView(
                controller: _tabController,
                children: _tabs.map((tab) => _buildTabContent(tab, templates)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(_TabInfo tab, List<TradeTemplate> allTemplates) {
    // 按分类过滤 + 按角色过滤
    final filtered = allTemplates.where((t) {
      if (!tab.categories.contains(t.category)) return false;
      return t.isVisibleTo(widget.isBuyer);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('暂无可用定型文', style: TextStyle(color: AppColors.text3)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final template = filtered[index];
        final isExpanded = _expandedIndex == index;

        if (template.hasAmount) {
          return _buildPriceTemplateItem(template, index, isExpanded);
        }
        return _buildTextTemplateItem(template);
      },
    );
  }

  /// 纯文字模板项：点击即发送
  Widget _buildTextTemplateItem(TradeTemplate template) {
    return InkWell(
      onTap: _isSending ? null : () => _sendTextMessage(template.content),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          template.content,
          style: const TextStyle(fontSize: 14, color: AppColors.text1),
        ),
      ),
    );
  }

  /// 含价格模板项：点击展开/收起金额输入
  Widget _buildPriceTemplateItem(
    TradeTemplate template,
    int index,
    bool isExpanded,
  ) {
    // 将模板文案按 {price} 拆分展示
    final parts = template.content.split('{price}');
    final beforePrice = parts.isNotEmpty ? parts[0] : '';
    final afterPrice = parts.length > 1 ? parts[1] : '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isExpanded ? AppColors.primary : AppColors.divider,
          width: isExpanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 模板文案行（点击展开/收起）
          InkWell(
            onTap: () {
              setState(() {
              if (_expandedIndex == index) {
                _expandedIndex = -1;
                _priceController.clear();
              } else {
                _expandedIndex = index;
                _priceController.clear();
              }
            });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  if (beforePrice.isNotEmpty)
                    Text(
                      beforePrice,
                      style: const TextStyle(fontSize: 14, color: AppColors.text1),
                    ),
                  if (isExpanded)
                    const Icon(Icons.expand_more, size: 18, color: AppColors.primary)
                  else
                    const Icon(Icons.expand_less, size: 18, color: AppColors.text3),
                  if (afterPrice.isNotEmpty)
                    Flexible(
                      child: Text(
                        afterPrice,
                        style: const TextStyle(fontSize: 14, color: AppColors.text1),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 展开态：金额输入行
          if (isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  const Text(
                    '¥',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: const InputDecoration(
                        hintText: '输入金额',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : () => _sendPriceMessage(template),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('发送', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 发送纯文字定型文消息
  Future<void> _sendTextMessage(String content) async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      await chatRepo.sendMessage(widget.sessionId, content);
      // 刷新消息列表
      ref.invalidate(messagesProvider(widget.sessionId));
      // 标记已读
      await chatRepo.markRead(widget.sessionId);
      ref.invalidate(chatUnreadCountProvider);
      widget.onSent();
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppToast(context, '发送失败：$e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// 发送含价格的定型文消息，并同步更新报价
  Future<void> _sendPriceMessage(TradeTemplate template) async {
    final priceText = _priceController.text.trim();
    if (priceText.isEmpty) {
      showAppToast(context, '请输入金额');
      return;
    }
    final yuan = double.tryParse(priceText);
    if (yuan == null || yuan <= 0) {
      showAppToast(context, '请输入有效金额');
      return;
    }
    final amountFen = (yuan * 100).round();

    // 替换 {price} 生成实际消息内容
    final messageContent = template.content.replaceAll('{price}', priceText);

    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      // 1. 先更新报价
      final tradeRepo = ref.read(tradeRepositoryProvider);
      final quote = Quote(
        inquiryId: widget.inquiryId,
        amount: amountFen,
        licenseType: widget.licenseType ?? 'non_exclusive',
        role: widget.isSeller ? 'seller' : 'buyer',
      );
      if (widget.isSeller) {
        await tradeRepo.appCreateQuote(quote);
      } else {
        await tradeRepo.appCounterOffer(quote);
      }
      // 刷新报价状态
      ref.invalidate(latestQuoteProvider(widget.inquiryId));

      // 2. 发送定型文消息
      final chatRepo = ref.read(chatRepositoryProvider);
      await chatRepo.sendMessage(widget.sessionId, messageContent);
      // 刷新消息列表
      ref.invalidate(messagesProvider(widget.sessionId));
      // 标记已读
      await chatRepo.markRead(widget.sessionId);
      ref.invalidate(chatUnreadCountProvider);
      widget.onSent();
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppToast(context, '发送失败：$e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}

/// Tab 信息（标签 + 关联的分类集合）
class _TabInfo {
  const _TabInfo({required this.label, required this.categories});
  final String label;
  final Set<String> categories;
}
