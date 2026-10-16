import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../user_center/data/paged_data.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

/// 发票管理页
///
/// 发票列表（状态筛选）+ 右上角申请按钮（底部表单）。
class InvoicePage extends ConsumerStatefulWidget {
  const InvoicePage({super.key});

  @override
  ConsumerState<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends ConsumerState<InvoicePage> {
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(
      invoiceListProvider(InvoiceListParams(status: _statusFilter)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('发票管理'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showApplyForm(context),
          ),
        ],
      ),
      body: Container(
        color: Colors.grey[100],
        child: Column(
          children: [
            _buildStatusFilter(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(invoiceListProvider(
                    InvoiceListParams(status: _statusFilter),
                  ));
                },
                child: invoices.when(
                  data: (paged) => _buildList(paged),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败: $e')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilter() {
    const filters = <String?>[null, 'pending', 'issued', 'rejected'];
    const labels = ['全部', '待审核', '已开具', '已拒绝'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(filters.length, (i) {
            final selected = _statusFilter == filters[i];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labels[i]),
                selected: selected,
                selectedColor: AppColors.primary.withOpacity(0.2),
                onSelected: (_) {
                  setState(() => _statusFilter = filters[i]);
                },
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildList(PagedData<Invoice> paged) {
    if (paged.list.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('暂无发票记录', style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showApplyForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('申请发票'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: paged.list.length,
      itemBuilder: (context, index) => _InvoiceCard(invoice: paged.list[index]),
    );
  }

  void _showApplyForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _InvoiceApplySheet(),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(invoice.status);
    final statusLabel = InvoiceStatus.label(invoice.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12)),
                ),
                Text(invoice.amountYuan, style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Text('${invoice.invoiceNo ?? "-"} · ${invoice.typeName}',
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              [invoice.orderNo, invoice.workTitle].where((s) => s != null && s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text('抬头: ${invoice.title ?? "-"}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (invoice.status == 'rejected' && invoice.rejectReason != null) ...[
              const SizedBox(height: 6),
              Text('拒绝原因: ${invoice.rejectReason}',
                style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],
            const SizedBox(height: 6),
            Text(formatDate(invoice.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'issued': return Colors.green;
      case 'rejected': return Colors.red;
      default: return Colors.grey;
    }
  }
}

class _InvoiceApplySheet extends ConsumerStatefulWidget {
  const _InvoiceApplySheet();

  @override
  ConsumerState<_InvoiceApplySheet> createState() => _InvoiceApplySheetState();
}

class _InvoiceApplySheetState extends ConsumerState<_InvoiceApplySheet> {
  final _formKey = GlobalKey<FormState>();
  String? _invoiceType = 'normal';
  final _titleController = TextEditingController();
  final _taxNoController = TextEditingController();
  final _emailController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic>? _selectedOrder;
  bool _isLoadingOrders = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      final orders = await ref.read(tradeRepositoryProvider).invoiceableOrders();
      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoadingOrders = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingOrders = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _taxNoController.dispose();
    _emailController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('申请发票', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // 订单选择器
            const Text('选择订单', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            if (_isLoadingOrders)
              const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()))
            else if (_orders.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100], borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: Text('暂无可开票订单', style: TextStyle(color: Colors.grey))),
              )
            else
              DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedOrder,
                decoration: const InputDecoration(labelText: '订单', border: OutlineInputBorder()),
                items: _orders.map((o) {
                  final title = o['workTitle'] as String? ?? '-';
                  final orderNo = o['orderNo'] as String? ?? '-';
                  final amount = o['amount'] as int? ?? 0;
                  return DropdownMenuItem(
                    value: o,
                    child: Text('$orderNo · $title · ¥${(amount / 100).toStringAsFixed(2)}'),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedOrder = v;
                    if (v != null) {
                      final amount = v['amount'] as int? ?? 0;
                      _amountController.text = (amount / 100).toStringAsFixed(2);
                    }
                  });
                },
                validator: (v) => v == null ? '请选择订单' : null,
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '金额（元）', border: OutlineInputBorder()),
              validator: (v) => v == null || v.isEmpty ? '请输入金额' : null,
            ),
            const SizedBox(height: 12),
            const Text('发票类型', style: TextStyle(fontSize: 14)),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('普通发票'),
                  selected: _invoiceType == 'normal',
                  onSelected: (_) => setState(() => _invoiceType = 'normal'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('增值税专用发票'),
                  selected: _invoiceType == 'special',
                  onSelected: (_) => setState(() => _invoiceType = 'special'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '发票抬头', border: OutlineInputBorder()),
              validator: (v) => v == null || v.isEmpty ? '请输入发票抬头' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _taxNoController,
              decoration: const InputDecoration(labelText: '税号（选填）', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: '接收邮箱（选填）', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting || _orders.isEmpty ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('提交申请', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(tradeRepositoryProvider).applyInvoice({
        'orderId': _selectedOrder!['orderId'],
        'invoiceType': _invoiceType,
        'title': _titleController.text,
        'taxNo': _taxNoController.text.isNotEmpty ? _taxNoController.text : null,
        'email': _emailController.text.isNotEmpty ? _emailController.text : null,
        'amount': double.tryParse(_amountController.text) ?? 0,
      });
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(invoiceListProvider(const InvoiceListParams()));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('发票申请已提交')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('申请失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
