/// 版权管理主页（App 端）。
///
/// 从「我的」快捷入口进入，提供版权申请表单、申请列表、交割和证书管理入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';

/// 版权管理主页
class CopyrightHomePage extends ConsumerWidget {
  const CopyrightHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('版权管理'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 功能入口区域
            _buildFunctionCard(
              context,
              icon: Icons.edit_document,
              title: '版权申请',
              subtitle: '填写并提交版权登记申请',
              color: AppColors.primary,
              onTap: () => context.push(RoutePath.copyrightForm),
            ),
            const SizedBox(height: 12),
            _buildFunctionCard(
              context,
              icon: Icons.assignment_outlined,
              title: '申请列表',
              subtitle: '查看已提交的版权申请进度',
              color: const Color(0xFF1890FF),
              onTap: () => context.push(RoutePath.copyrightApplicationList),
            ),
            const SizedBox(height: 12),
            _buildFunctionCard(
              context,
              icon: Icons.workspace_premium_outlined,
              title: '版权证书',
              subtitle: '查看已获得的版权证书',
              color: const Color(0xFF52C41A),
              onTap: () => context.push(RoutePath.copyrightCertificateList),
            ),
            const SizedBox(height: 12),
            _buildFunctionCard(
              context,
              icon: Icons.swap_horiz_outlined,
              title: '版权交割',
              subtitle: '付款后的交割材料上传与确认收货',
              color: const Color(0xFFFA8C16),
              onTap: () => context.push(RoutePath.copyrightDeliveryList),
            ),
            const SizedBox(height: 24),
            // 说明区域
            _buildInfoSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildFunctionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                '版权保护说明',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoItem('1. 提交版权申请后，平台将审核您的申请材料'),
          _buildInfoItem('2. 审核通过后，系统将提交到第三方版权中心'),
          _buildInfoItem('3. 版权中心审核通过后，将自动签发电子证书'),
          _buildInfoItem('4. 您可以在"版权证书"中查看和下载证书'),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '•  ',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.text2,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
