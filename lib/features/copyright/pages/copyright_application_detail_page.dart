/// 版权申请详情页（App 端）。
/// 
/// 支持展示申请详情和交割详情两种类型。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/common_views.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/services/native_file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../data/copyright_models.dart';
import '../data/copyright_providers.dart';
import '../widgets/material_upload_section.dart';
import '../widgets/image_viewer.dart';

class _PendingDeliveryFile {
  const _PendingDeliveryFile({
    required this.fileName,
    required this.fileType,
    required this.fileUrl,
    required this.fileSize,
  });

  final String fileName;
  final String fileType;
  final String fileUrl;
  final int fileSize;
}

/// 详情页类型
enum DetailPageType {
  application, // 申请详情
  delivery,    // 交割详情
}

/// 版权申请/交割详情页
class CopyrightApplicationDetailPage extends ConsumerStatefulWidget {
  final int id;
  final DetailPageType type;

  /// [id] 与 [applyId] 二选一；路由侧历史参数名为 applyId。
  const CopyrightApplicationDetailPage({
    super.key,
    int? id,
    int? applyId,
    this.type = DetailPageType.application,
  }) : id = id ?? applyId ?? 0;

  const CopyrightApplicationDetailPage.fromApplyId({
    super.key,
    required int applyId,
    this.type = DetailPageType.application,
  }) : id = applyId;


  /// 路由兼容：使用 applyId 构造申请详情。


  // 便捷构造函数
  const CopyrightApplicationDetailPage.application({
    super.key,
    required int applyId,
  }) : id = applyId, type = DetailPageType.application;

  const CopyrightApplicationDetailPage.delivery({
    super.key,
    required int deliveryId,
  }) : id = deliveryId, type = DetailPageType.delivery;

  @override
  ConsumerState<CopyrightApplicationDetailPage> createState() =>
      _CopyrightApplicationDetailPageState();
}

class _CopyrightApplicationDetailPageState
    extends ConsumerState<CopyrightApplicationDetailPage> {
  final List<_PendingDeliveryFile> _pendingFiles = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final provider = ref.read(copyrightProvider);
    if (widget.type == DetailPageType.application) {
      await provider.loadApplicationDetail(widget.id);
    } else {
      await provider.loadDeliveryDetail(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(copyrightProvider);

    if (widget.type == DetailPageType.application) {
      return _buildApplicationDetail(provider);
    } else {
      return _buildDeliveryDetail(provider);
    }
  }

  // ==================== 申请详情 ====================

  Widget _buildApplicationDetail(provider) {
    if (provider.applicationDetailLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('申请详情'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.applicationDetailError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('申请详情'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: ErrorView(
          message: provider.applicationDetailError!,
          onRetry: _loadData,
        ),
      );
    }

    final application = provider.currentApplication;
    if (application == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('申请详情'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: EmptyView(
          icon: Icons.assignment_outlined,
          message: '申请记录不存在',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('申请详情'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 状态卡片
            _buildStatusCard(application),
            const SizedBox(height: 16),
            // 作品信息
            _buildWorkInfoCard(application),
            const SizedBox(height: 16),
            // 申请材料
            if (_hasMaterials(application))
              _buildMaterialsCard(application),
            if (_hasMaterials(application))
              const SizedBox(height: 16),
            // 申请信息
            _buildInfoCard(application),
            const SizedBox(height: 16),
            // 操作按钮
            _buildActionButtons(application),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(CopyrightApplication application) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _getStatusColor(application.status),
              _getStatusColor(application.status).withOpacity(0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(application.status),
                  size: 32,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    application.statusLabel,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (application.statusDescription.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                application.statusDescription,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkInfoCard(CopyrightApplication application) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '作品信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('作品名称', application.workName),
            if (application.workType != null) ...[ 
              _buildDivider(),
              _buildDetailRow('作品类型', application.workType!),
            ],
            if (application.workCategory != null) ...[ 
              _buildDivider(),
              _buildDetailRow('作品类别', application.workCategory!),
            ],
            if (application.workIntro != null && application.workIntro!.isNotEmpty) ...[ 
              _buildDivider(),
              _buildDetailRow('作品简介', application.workIntro!, maxLines: 5),
            ],
            if (application.workCompletionDate != null) ...[ 
              _buildDivider(),
              _buildDetailRow('创作完成日期', application.workCompletionDate!),
            ],
            if (application.workPublishDate != null) ...[ 
              _buildDivider(),
              _buildDetailRow('首次发表日期', application.workPublishDate!),
            ],
            if (application.workCoverUrl != null && application.workCoverUrl!.isNotEmpty) ...[ 
              _buildDivider(),
              const SizedBox(height: 8),
              const Text(
                '作品封面',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  application.workCoverUrl!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: AppColors.divider,
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 48, color: AppColors.text3),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasMaterials(CopyrightApplication application) {
    // 优先检查新的分类材料字段
    if ((application.originalityProof != null && application.originalityProof!.isNotEmpty) ||
        (application.authorIdentityDoc != null && application.authorIdentityDoc!.isNotEmpty) ||
        (application.creationProcess != null && application.creationProcess!.isNotEmpty) ||
        (application.otherProof != null && application.otherProof!.isNotEmpty)) {
      return true;
    }
    
    // 兼容旧字段
    return (application.workFileUrl != null && application.workFileUrl!.isNotEmpty) ||
           (application.identityProofUrl != null && application.identityProofUrl!.isNotEmpty) ||
           (application.creationProofUrl != null && application.creationProofUrl!.isNotEmpty) ||
           (application.otherMaterialsUrls != null && application.otherMaterialsUrls!.isNotEmpty);
  }

  Widget _buildMaterialsCard(CopyrightApplication application) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '申请材料',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 16),
            
            // 合并显示所有申请材料（不再分类显示）。
            ..._buildAllMaterialsSection(application),
            
            // 兼容旧字段显示（如果没有新字段数据）
            if (_isOldFormatData(application)) ...[
              if (application.identityProofUrl != null && application.identityProofUrl!.isNotEmpty) ...[ 
                _buildOldMaterialItem('身份证明', application.identityProofUrl!),
                const SizedBox(height: 12),
              ],
              if (application.creationProofUrl != null && application.creationProofUrl!.isNotEmpty) ...[
                _buildOldMaterialItem('创作说明', application.creationProofUrl!),
                const SizedBox(height: 12),
              ],
              if (application.workFileUrl != null && application.workFileUrl!.isNotEmpty) ...[
                _buildOldMaterialItem('作品文件', application.workFileUrl!),
                const SizedBox(height: 12),
              ],
              if (application.otherMaterialsUrls != null && application.otherMaterialsUrls!.isNotEmpty)
                _buildOldMaterialItem('其他材料', application.otherMaterialsUrls!),
            ],
          ],
        ),
      ),
    );
  }

  // 合并显示所有申请材料
  List<Widget> _buildAllMaterialsSection(CopyrightApplication application) {
    final allMaterials = <MaterialFile>[];
    
    // 合并所有分类材料
    if (application.originalityProof != null && application.originalityProof!.isNotEmpty) {
      allMaterials.addAll(materialFilesFromJson(application.originalityProof));
    }
    if (application.authorIdentityDoc != null && application.authorIdentityDoc!.isNotEmpty) {
      allMaterials.addAll(materialFilesFromJson(application.authorIdentityDoc));
    }
    if (application.creationProcess != null && application.creationProcess!.isNotEmpty) {
      allMaterials.addAll(materialFilesFromJson(application.creationProcess));
    }
    if (application.otherProof != null && application.otherProof!.isNotEmpty) {
      allMaterials.addAll(materialFilesFromJson(application.otherProof));
    }
    
    if (allMaterials.isEmpty) return [];
    
    return [
      _buildMaterialSection('申请材料', allMaterials),
    ];
  }

  // 判断是否为旧格式数据
  bool _isOldFormatData(CopyrightApplication application) {
    return (application.originalityProof == null || application.originalityProof!.isEmpty) &&
           (application.authorIdentityDoc == null || application.authorIdentityDoc!.isEmpty) &&
           (application.creationProcess == null || application.creationProcess!.isEmpty) &&
           (application.otherProof == null || application.otherProof!.isEmpty);
  }

  Widget _buildMaterialSection(String title, List<MaterialFile> files) {
    if (files.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
          ),
        ),
        const SizedBox(height: 8),
        ...files.map((file) => _buildMaterialFileItem(file)),
      ],
    );
  }

  Widget _buildMaterialFileItem(MaterialFile file) {
    return InkWell(
      onTap: () {
        // 打开预览
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MaterialPreviewPage(
              url: file.url,
              filename: file.filename,
              fileType: file.fileType,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              file.isImage
                  ? Icons.image
                  : file.isPdf
                      ? Icons.picture_as_pdf
                      : Icons.insert_drive_file,
              color: file.isImage
                  ? Colors.green
                  : file.isPdf
                      ? Colors.red
                      : AppColors.text2,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                file.filename,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.text1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              file.isImage ? Icons.visibility : Icons.visibility_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOldMaterialItem(String label, String url) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, color: AppColors.text2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  url,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.text1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(CopyrightApplication application) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '申请信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('作品名称', application.workName),
            _buildDivider(),
            _buildDetailRow('申请编号', application.applyNo),
            if (application.externalApplyNo != null) ...[
              _buildDivider(),
              _buildDetailRow('第三方编号', application.externalApplyNo!),
            ],
            if (application.centerName.isNotEmpty) ...[
              _buildDivider(),
              _buildDetailRow('版权中心', application.centerName),
            ],
            _buildDivider(),
            _buildDetailRow('申请人', application.userName),
            _buildDivider(),
            _buildDetailRow('申请时间', application.createTime ?? '-'),
            if (application.certTime != null) ...[
              _buildDivider(),
              _buildDetailRow('发证时间', application.certTime!),
            ],
            if (application.certNo != null) ...[
              _buildDivider(),
              _buildDetailRow('证书编号', application.certNo!),
            ],
            if (application.remark != null && application.remark!.isNotEmpty) ...[
              _buildDivider(),
              _buildDetailRow('备注', application.remark!, maxLines: 3),
            ],
            if (application.rejectReason != null &&
                application.rejectReason!.isNotEmpty) ...[
              _buildDivider(),
              _buildDetailRow(
                '驳回原因',
                application.rejectReason!,
                maxLines: 5,
                valueColor: const Color(0xFFF5222D),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(CopyrightApplication application) {
    final bool canModify = application.status == CopyrightApplicationStatus.pending;
    
    if (!canModify && !application.canResubmit && !application.isCertificated) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // pending状态：显示删除按钮
        if (canModify)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _showDeleteConfirmDialog(application),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除申请'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        // rejected状态：重新提交按钮
        if (application.canResubmit)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                RoutePath.copyrightFormUrl(applyId: application.applyId),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('重新提交申请'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        // certificated状态：查看证书按钮
        if (application.isCertificated && application.certId != null) ...[
          if (application.canResubmit) const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                RoutePath.copyrightCertificateDetailUrl(application.certId!),
              ),
              icon: const Icon(Icons.workspace_premium),
              label: const Text('查看版权证书'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF52C41A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog(CopyrightApplication app) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${app.workName}」的版权申请吗？\n\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteApplication(app.applyId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  /// 删除申请
  Future<void> _deleteApplication(int applyId) async {
    try {
      final provider = ref.read(copyrightProvider);
      await provider.deleteApplication(applyId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('删除成功'),
            backgroundColor: Colors.green,
          ),
        );
        // 返回列表页
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 跳转到编辑页面


  Widget _buildDetailRow(
    String label,
    String value, {
    int maxLines = 1,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.text2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: valueColor ?? AppColors.text1,
                fontWeight: FontWeight.w500,
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: AppColors.divider,
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case CopyrightApplicationStatus.pending:
        return const Color(0xFFFFA940);
      case CopyrightApplicationStatus.approved:
      case CopyrightApplicationStatus.submitted:
        return const Color(0xFF1890FF);
      case CopyrightApplicationStatus.reviewing:
        return const Color(0xFF722ED1);
      case CopyrightApplicationStatus.certificated:
        return const Color(0xFF52C41A);
      case CopyrightApplicationStatus.rejected:
        return const Color(0xFFF5222D);
      default:
        return AppColors.text2;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case CopyrightApplicationStatus.pending:
        return Icons.schedule;
      case CopyrightApplicationStatus.approved:
      case CopyrightApplicationStatus.submitted:
        return Icons.upload;
      case CopyrightApplicationStatus.reviewing:
        return Icons.hourglass_empty;
      case CopyrightApplicationStatus.certificated:
        return Icons.check_circle;
      case CopyrightApplicationStatus.rejected:
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  // ==================== 交割详情 ====================

  Widget _buildDeliveryDetail(provider) {
    if (provider.deliveryLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('交割详情'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final delivery = provider.currentDelivery;
    if (delivery == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('交割详情'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: EmptyView(message: '交割记录不存在'),
      );
    }

    final userId = ref.watch(authControllerProvider).user?.userId ?? 0;
    final isSeller = userId == delivery.sellerId;
    final isBuyer = userId == delivery.buyerId;
    final canUpload = isSeller && delivery.status == 'pending_upload';
    final canConfirm = isBuyer && delivery.status == 'pending_confirm';

    return Scaffold(
      appBar: AppBar(
        title: const Text('交割详情'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildDeliveryBasicInfo(delivery),
              const SizedBox(height: 12),
              _buildDeliveryOrderInfo(delivery),
              const SizedBox(height: 12),
              _buildDeliveryContractInfo(delivery),
              if (delivery.files != null && delivery.files!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDeliveryFiles(delivery),
              ],
              if (canUpload) ...[
                const SizedBox(height: 12),
                _buildDeliveryUploadSection(),
              ],
              if (delivery.remark != null) ...[
                const SizedBox(height: 12),
                _buildDeliveryRemark(delivery),
              ],
              const SizedBox(height: 12),
              _buildDeliveryTimeline(delivery),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildDeliveryActionBar(
        delivery: delivery,
        canUpload: canUpload,
        canConfirm: canConfirm,
      ),
    );
  }

  Widget _buildDeliveryBasicInfo(CopyrightDelivery delivery) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                delivery.deliveryNo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              _buildDeliveryStatusBadge(delivery.status),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            delivery.workTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailRow('授权类型', delivery.licenseType.licenseTypeName),
          _buildDetailRow('交易金额', '¥${delivery.amount.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _buildDeliveryOrderInfo(CopyrightDelivery delivery) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '订单信息',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailRow('订单编号', delivery.orderNo),
          _buildDetailRow('买方', delivery.buyerName),
          _buildDetailRow('卖方', delivery.sellerName),
          if (delivery.certNo != null)
            _buildDetailRow('版权证书号', delivery.certNo!),
        ],
      ),
    );
  }

  Widget _buildDeliveryContractInfo(CopyrightDelivery delivery) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '合同信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push(
                  '${RoutePath.contractSign}?orderId=${delivery.orderId}',
                ),
                icon: const Icon(Icons.description, size: 18),
                label: const Text('查看合同'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow('合同编号', delivery.contractNo),
          if (delivery.contractSignTime != null)
            _buildDetailRow('签署时间', delivery.contractSignTime!),
        ],
      ),
    );
  }

  Widget _buildDeliveryFiles(CopyrightDelivery delivery) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '交割文件',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 12),
          ...delivery.files!.map((file) => _buildDeliveryFileItem(file)),
        ],
      ),
    );
  }

  Widget _buildDeliveryFileItem(DeliveryFile file) {
    return InkWell(
      onTap: () => _openDeliveryFile(file),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              _getDeliveryFileIcon(file.fileType),
              color: AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${file.fileType.fileTypeName} ${_formatDeliveryFileSize(file.fileSize)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download, size: 20),
              onPressed: () => _openDeliveryFile(file),
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryUploadSection() {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '上传交割材料',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '须至少上传 1 个文件，且必须包含版权证书（cert）',
            style: TextStyle(fontSize: 12, color: AppColors.text3),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildAddFileChip('证书', 'cert'),
              _buildAddFileChip('源文件', 'source'),
              _buildAddFileChip('文档', 'doc'),
              _buildAddFileChip('其他', 'other'),
            ],
          ),
          if (_pendingFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._pendingFiles.asMap().entries.map((e) {
              final i = e.key;
              final f = e.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_getDeliveryFileIcon(f.fileType), color: AppColors.primary),
                title: Text(f.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${f.fileType.fileTypeName} ${_formatDeliveryFileSize(f.fileSize)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _pendingFiles.removeAt(i)),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildAddFileChip(String label, String fileType) {
    return ActionChip(
      label: Text('+$label'),
      onPressed: _submitting ? null : () => _pickAndUploadDeliveryFile(fileType),
    );
  }

  Widget _buildDeliveryActionBar({
    required CopyrightDelivery delivery,
    required bool canUpload,
    required bool canConfirm,
  }) {
    if (!canUpload && !canConfirm) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: SafeArea(
          child: Text(
            delivery.status == 'completed'
                ? '交割已完成'
                : delivery.status == 'cancelled'
                    ? '交割已取消'
                    : delivery.status == 'pending_upload'
                        ? '等待卖方上传交割材料'
                        : '当前无需操作',
            style: const TextStyle(fontSize: 12, color: AppColors.text3),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting
                ? null
                : () {
                    if (canUpload) {
                      _submitDeliveryUpload(delivery.deliveryId);
                    } else if (canConfirm) {
                      _confirmDeliveryReceipt(delivery.deliveryId);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: canUpload ? AppColors.warning : AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              _submitting
                  ? '提交中...'
                  : canUpload
                      ? '提交交割'
                      : '确认收货',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadDeliveryFile(String fileType) async {
    try {
      final picked = await NativeFilePicker.pickAny(filenamePrefix: fileType);
      if (picked == null) return;
      showAppToast(context, '正在上传...');
      final url = await ref.read(copyrightProvider).apiService.uploadMaterialFileBytes(
            bytes: picked.bytes,
            fileName: picked.filename,
          );
      if (!mounted) return;
      setState(() {
        _pendingFiles.add(_PendingDeliveryFile(
          fileName: picked.filename,
          fileType: fileType,
          fileUrl: url,
          fileSize: picked.size,
        ));
      });
      showAppToast(context, '已添加：${picked.filename}');
    } catch (e) {
      if (mounted) showAppToast(context, '上传失败：$e');
    }
  }

  Future<void> _submitDeliveryUpload(int deliveryId) async {
    if (_pendingFiles.isEmpty) {
      showAppToast(context, '请至少上传 1 个文件');
      return;
    }
    if (!_pendingFiles.any((f) => f.fileType == 'cert')) {
      showAppToast(context, '必须上传版权证书文件');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(copyrightProvider).uploadDelivery(
            deliveryId,
            files: _pendingFiles
                .map((f) => {
                      'fileName': f.fileName,
                      'fileType': f.fileType,
                      'fileUrl': f.fileUrl,
                      'fileSize': f.fileSize,
                    })
                .toList(),
          );
      if (!mounted) return;
      setState(() {
        _pendingFiles.clear();
        _submitting = false;
      });
      showAppToast(context, '交割材料已提交，等待买方确认');
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showAppToast(context, '提交失败：$e');
      }
    }
  }

  Future<void> _confirmDeliveryReceipt(int deliveryId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('确认收货'),
        content: const Text('确认已收到交割材料？确认后订单将完成，此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('再想想')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('确认收货', style: TextStyle(color: AppColors.success)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _submitting = true);
    try {
      await ref.read(copyrightProvider).confirmDelivery(deliveryId);
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(context, '已确认收货，交割完成');
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showAppToast(context, '确认失败：$e');
      }
    }
  }

  void _openDeliveryFile(DeliveryFile file) {
    final url = file.fileUrl.trim();
    if (url.isEmpty) {
      showAppToast(context, '文件地址无效');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MaterialPreviewPage(
          url: url,
          filename: file.fileName,
          fileType: file.fileType,
        ),
      ),
    );
  }

  Widget _buildDeliveryRemark(CopyrightDelivery delivery) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '备注说明',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            delivery.remark!,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryTimeline(CopyrightDelivery delivery) {
    final events = <Map<String, String>>[];
    
    events.add({'time': delivery.createTime, 'event': '创建交割记录'});
    if (delivery.uploadTime != null) {
      events.add({'time': delivery.uploadTime!, 'event': '卖方上传交割文件'});
    }
    if (delivery.confirmTime != null) {
      events.add({'time': delivery.confirmTime!, 'event': '买方确认收货'});
    }
    if (delivery.completedTime != null) {
      events.add({'time': delivery.completedTime!, 'event': '交割完成'});
    }

    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '交割进度',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 16),
          ...events.asMap().entries.map((entry) {
            final isLast = entry.key == events.length - 1;
            return _buildDeliveryTimelineItem(
              entry.value['time']!,
              entry.value['event']!,
              isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDeliveryTimelineItem(String time, String event, bool isLast) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: AppColors.divider,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'pending_upload':
        color = Colors.orange;
        break;
      case 'pending_confirm':
        color = Colors.blue;
        break;
      case 'completed':
        color = Colors.green;
        break;
      case 'cancelled':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        status.deliveryStatusName,
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  IconData _getDeliveryFileIcon(String fileType) {
    switch (fileType) {
      case 'cert':
        return Icons.workspace_premium;
      case 'source':
        return Icons.description;
      case 'doc':
        return Icons.article;
      default:
        return Icons.attach_file;
    }
  }

  String _formatDeliveryFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
