import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'contract_list_page.dart';
import 'order_list_page.dart';

class OrderContractPage extends StatelessWidget {
  const OrderContractPage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('订单管理'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            tabs: [Tab(text: '订单'), Tab(text: '合同')],
          ),
        ),
        body: const TabBarView(
          children: [
            OrderListPage(embedded: true),
            ContractListPage(embedded: true),
          ],
        ),
      ),
    );
  }
}
