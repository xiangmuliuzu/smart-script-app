/// 购买获得的版权材料详情（预览 / 下载）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/certificate_download_helper.dart';
import '../data/copyright_models.dart';
import '../data/copyright_providers.dart';
import '../widgets/image_viewer.dart';

/// 买方购买获得的版权材料详情页。
class BuyerCopyrightDetailPage extends ConsumerStatefulWidget {
  const BuyerCopyrightDetailPage({
    super.key,
    required this.fileId,
  });

  final int fileId;

  @override
  ConsumerState<BuyerCopyrightDetailPage> createState() =>
      _BuyerCopyrightDetailPageState();
}

class _BuyerCopyrightDetailPageState
    extends ConsumerState<BuyerCopyrightDetailPage> {
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(copyrightProvider).loadPurchasedCopyrightDetail(widget.fileId);
    });
  }

  Future<void> _preview(BuyerCopyrightMaterial item) async {
    final url = item.fileUrl.trim();
    if (url.isEmpty) {
      _toast('暂无可预览的文件地址');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MaterialPreviewPage(
          url: url,
          filename: item.fileName,
          fileType: item.previewKind,
        ),
      ),
    );
  }

  Future<void> _download(BuyerCopyrightMaterial item) async {
    final raw = item.fileUrl.trim();
    if (raw.isEmpty) {
      _toast('暂无可下载的文件地址');
      return;
    }

    setState(() => _downloading = true);
    try {
      final url = AppConfig.resolveAssetUrl(raw);
      final fileName = (item.fileName.trim().isEmpty)
          ? '版权材料_${item.fileId}'
          : item.fileName.trim();
      final helper = CertificateDownloadHelper.create();
      final file = await helper.saveRemoteFile(
        url: url,
        fileName: fileName,
        mimeType: _mimeOf(fileName, item.previewKind),
      );

      var opened = false;
      try {
        opened = await launchUrl(
          Uri.file(file.path),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}

      if (!mounted) return;
      final where = helper.savedToPublicDownloads
          ? '系统「下载」'
          : '应用私有目录（文件管理器默认不可见）';
      _toast(
        opened ? '材料已下载并打开' : '材料已保存到$where：$fileName',
      );
    } catch (e) {
      if (mounted) _toast('下载失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  static String _mimeOf(String fileName, String previewKind) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf') || previewKind == 'pdf') {
      return 'application/pdf';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(copyrightProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('版权材料详情'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: _buildBody(provider),
      bottomNavigationBar: _buildActions(provider.currentPurchased),
    );
  }

  Widget _buildBody(provider) {
    if (provider.purchasedDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.purchasedDetailError != null) {
      return ErrorView(
        message: provider.purchasedDetailError!,
        onRetry: () => provider.loadPurchasedCopyrightDetail(widget.fileId),
      );
    }
    final item = provider.currentPurchased as BuyerCopyrightMaterial?;
    if (item == null) {
      return const EmptyView(
        icon: Icons.workspace_premium_outlined,
        message: '版权材料不存在',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.workTitle.isEmpty ? '作品' : '《${item.workTitle}》',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const SizedBox(height: 16),
              _row('卖家', item.sellerName.isEmpty ? '-' : item.sellerName),
              _row('交割时间', item.deliveryTime.isEmpty ? '-' : item.deliveryTime),
              _row(
                '材料名称',
                item.fileName.isEmpty ? '未命名材料' : item.fileName,
              ),
              _row(
                '订单号',
                item.orderNo.isEmpty
                    ? (item.orderId > 0 ? '#${item.orderId}' : '-')
                    : item.orderNo,
              ),
              if (item.deliveryNo.isNotEmpty)
                _row('交割单号', item.deliveryNo),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '确认收货后，卖方交割时上传的版权证书会出现在此；可在线预览或下载到本地。',
          style: TextStyle(fontSize: 13, color: AppColors.text3, height: 1.4),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.text3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: AppColors.text1),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildActions(BuyerCopyrightMaterial? item) {
    if (item == null) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _preview(item),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('在线预览'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _downloading ? null : () => _download(item),
                icon: _downloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: Text(_downloading ? '下载中…' : '下载'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
