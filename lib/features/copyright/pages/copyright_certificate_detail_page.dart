/// 版权证书详情页（App 端）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/common_views.dart';
import '../../../core/theme/app_colors.dart';
import '../data/copyright_models.dart';
import '../data/copyright_providers.dart';

/// 版权证书详情页
class CopyrightCertificateDetailPage extends ConsumerStatefulWidget {
  final int certId;

  const CopyrightCertificateDetailPage({
    super.key,
    required this.certId,
  });

  @override
  ConsumerState<CopyrightCertificateDetailPage> createState() =>
      _CopyrightCertificateDetailPageState();
}

class _CopyrightCertificateDetailPageState
    extends ConsumerState<CopyrightCertificateDetailPage> {
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final provider = ref.read(copyrightProvider);
    await provider.loadCertificateDetail(widget.certId);
  }

  Future<void> _downloadCertificate() async {
    setState(() {
      _downloading = true;
    });

    try {
      final provider = ref.read(copyrightProvider);
      final url = await provider.downloadCertificatePdf(widget.certId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('证书下载链接：$url')),
        );
        // 这里可以集成下载管理器或打开浏览器
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
        });
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(copyrightProvider);

    if (provider.certificateDetailLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('证书详情'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.certificateDetailError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('证书详情'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: ErrorView(
          message: provider.certificateDetailError!,
          onRetry: _loadData,
        ),
      );
    }

    final certificate = provider.currentCertificate;
    if (certificate == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('证书详情'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: EmptyView(
          icon: Icons.workspace_premium_outlined,
          message: '证书不存在',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('证书详情'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          if (certificate.isIssued)
            IconButton(
              icon: _downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              onPressed: _downloading ? null : _downloadCertificate,
              tooltip: '下载证书',
            ),
        ],
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 证书头部卡片
            _buildCertificateHeader(certificate),
            const SizedBox(height: 16),
            // 证书信息
            _buildCertificateInfo(certificate),
            const SizedBox(height: 16),
            // 区块链信息
            if (certificate.blockchainHash != null)
              _buildBlockchainInfo(certificate),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateHeader(CopyrightCert certificate) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF52C41A),
              Color(0xFF73D13D),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '版权证书',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              certificate.certNo,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                certificate.statusLabel,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateInfo(CopyrightCert certificate) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '证书信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              '作品名称',
              certificate.workName,
              copiable: false,
            ),
            _buildDivider(),
            _buildDetailRow(
              '证书编号',
              certificate.certNo,
              copiable: true,
            ),
            _buildDivider(),
            _buildDetailRow(
              '权利人',
              certificate.userName,
              copiable: false,
            ),
            _buildDivider(),
            _buildDetailRow(
              '申请时间',
              certificate.applyTime ?? '-',
              copiable: false,
            ),
            _buildDivider(),
            _buildDetailRow(
              '签发时间',
              certificate.certTime ?? '-',
              copiable: false,
            ),
            if (certificate.remark != null && certificate.remark!.isNotEmpty) ...[
              _buildDivider(),
              _buildDetailRow(
                '备注',
                certificate.remark!,
                maxLines: 3,
                copiable: false,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBlockchainInfo(CopyrightCert certificate) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1890FF).withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF1890FF).withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.verified_user, color: Color(0xFF1890FF), size: 24),
                SizedBox(width: 8),
                Text(
                  '区块链存证',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1890FF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '该证书已上链存证，保证真实性和不可篡改。',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key, size: 16, color: Color(0xFF1890FF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      certificate.blockchainHash!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text1,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => _copyToClipboard(
                      certificate.blockchainHash!,
                      '区块链哈希',
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    int maxLines = 1,
    bool copiable = false,
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
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.text1,
                fontWeight: FontWeight.w500,
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (copiable)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => _copyToClipboard(value, label),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
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
}
