import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/native_file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../seal/data/seal_models.dart';
import '../../seal/data/seal_providers.dart';
import '../data/contract_providers.dart';
import '../data/contract_repository.dart';
import '../data/trade_models.dart';

/// 合同签署页面。
///
/// 从上到下：状态栏 → 合同内容（WebView）→ 签名区域 → 确认签署按钮。
/// 支持手写签名（Canvas）和印章（已审核通过的印章列表），满足其一即可。
class ContractSignPage extends ConsumerStatefulWidget {
  const ContractSignPage({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<ContractSignPage> createState() => _ContractSignPageState();
}

class _ContractSignPageState extends ConsumerState<ContractSignPage> {
  /// 手写签名画布控制器
  late final SignatureController _signatureController;

  /// WebView 控制器
  late final WebViewController _webViewController;

  /// 手写签名图片字节（绘制完成后赋值）
  Uint8List? _signatureBytes;

  /// 选中的印章
  SealItem? _selectedSeal;

  /// 选中印章时预下载的印章图片字节（避免提交时慢网等待）
  Uint8List? _selectedSealBytes;



  /// 是否正在提交
  bool _submitting = false;

  /// 已加载过 HTML 的订单 ID（避免 build 重复 loadHtmlString 导致 WebView 白屏/闪烁）
  int? _loadedOrderId;

  /// 上传件拖拽定位（提交签署时序列化为 placements JSON）
  List<Map<String, dynamic>> _placements = [];

  @override
  void initState() {
    super.initState();
    _signatureController = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 3,
    );
    // ignore: prefer_const_constructors
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled);
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contractAsync =
        ref.watch(contractByOrderProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('合同签署'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          // 编辑正文条款：仅待签署且双方均未签时可改，否则弹锁定提示
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '编辑内容',
            onPressed: () {
              final contract = contractAsync.value;
              if (contract == null) return;
              if (contract.isUploaded) {
                showAppToast(context, '上传合同不支持在线编辑，可重新上传或切回模板');
                return;
              }
              if (!contract.isEditable) {
                showAppToast(context, '合同已进入签署，内容已锁定，不可修改');
                return;
              }
              _openContentEditor(contract);
            },
          ),
          // 合同来源管理：未锁定可上传 PDF / 切回模板，锁定则提示
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: '合同来源',
            onPressed: () => _openSourceMenu(contractAsync.value),
          ),
          // 刷新同步对方签署状态（partial_signed → completed）；refresh 保留旧内容不闪 loading
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新签署状态',
            onPressed: () {
              final _ = ref.refresh(contractByOrderProvider(widget.orderId));
            },
          ),
        ],
      ),
      body: contractAsync.when(
        // 下拉刷新时保留旧内容，避免整页闪烁 loading
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: '加载合同失败: $e'),
        data: (contract) {
          if (contract == null) {
            return const ErrorView(message: '该订单尚未生成合同');
          }
          // 加载合同 HTML 到 WebView（每个订单只加载一次，后续状态刷新不重复加载）
          if (_loadedOrderId != widget.orderId && !contract.isUploaded) {
            _loadedOrderId = widget.orderId;
            _loadContractHtml(contract);
          }
          // completed 状态：展示已签署合同内容 + PDF 入口
          if (contract.isCompleted) {
            return _buildCompletedView(contract);
          }
          // WebView 弹性占满剩余空间（内部滚动阅读合同），签名区固定在下部；
          // WebView 平台视图会吃掉拖动手势，刷新改由 AppBar 按钮触发
          return Column(
            children: [
              _buildStatusBar(contract),
              Expanded(child: _buildSigningContentArea(contract)),
              SingleChildScrollView(
                child: Column(
                  children: [
                    _buildSignatureArea(),
                    if (_selectedSeal != null) _buildSealPreview(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              _buildSubmitBar(contract),
            ],
          );
        },
      ),
    );
  }

  /// 合同状态栏
  Widget _buildStatusBar(ContractDetail contract) {
    final Color color;
    final String desc;
    switch (contract.status) {
      case ContractStatus.pending:
        color = AppColors.warning;
        desc = '合同待签署，请双方各自完成签署';
        break;
      case ContractStatus.partialSigned:
        color = AppColors.primary;
        final who = contract.isBuyerSigned ? '买方' : '卖方';
        desc = '$who已签署，等待另一方签署';
        break;
      default:
        color = AppColors.success;
        desc = contract.statusLabel;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, color: color, size: 18),
              const SizedBox(width: 6),
              Text('合同 ${contract.contractNo ?? ''}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(desc, style: TextStyle(fontSize: 13, color: color.withOpacity(0.8))),
          const SizedBox(height: 8),
          Row(
            children: [
              _signTag('买方', contract.isBuyerSigned),
              const SizedBox(width: 8),
              _signTag('卖方', contract.isSellerSigned),
            ],
          ),
        ],
      ),
    );
  }

  Widget _signTag(String party, bool signed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: signed ? AppColors.success.withOpacity(0.1) : AppColors.fill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$party ${signed ? '✓ 已签' : '○ 未签'}',
        style: TextStyle(
          fontSize: 12,
          color: signed ? AppColors.success : AppColors.text3,
        ),
      ),
    );
  }

  /// 合同内容区域（WebView 弹性占满，渲染 HTML）
  Widget _buildContractContent(ContractDetail contract) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: WebViewWidget(controller: _webViewController),
      ),
    );
  }

  void _loadContractHtml(ContractDetail contract) {
    final html = contract.content ?? '<p>合同内容加载中...</p>';
    // 指定 baseUrl：合同内 /profile/ 相对路径图片（对方签名图）才能解析加载。
    // /profile 为 root-relative，实际解析到站点 origin；生产 Caddy 与直连后端均提供该路径。
    _webViewController.loadHtmlString(html, baseUrl: AppConfig.baseUrl);
  }

  /// 签署区内容：上传件走分页拖拽定位，模板件走 WebView。
  Widget _buildSigningContentArea(ContractDetail contract) {
    if (contract.isUploaded) {
      return _PdfPlacementViewer(
        pageImageUrls: contract.pageImageUrls,
        signatureBytes: _signatureBytes,
        sealFullUrl: _selectedSeal != null && _selectedSeal!.sealImageUrl.isNotEmpty
            ? AppConfig.resolveAssetUrl(_selectedSeal!.sealImageUrl)
            : null,
        onPlacementsChanged: (p) => _placements = p,
      );
    }
    return _buildContractContent(contract);
  }

  /// 上传件已完成：只读分页展示（盖章结果在最终 PDF 中，页面图为签署底稿）。
  Widget _buildUploadedReadonly(ContractDetail contract) {
    final urls = contract.pageImageUrls;
    if (urls.isEmpty) {
      return const Center(child: Text('上传合同无可预览页面', style: TextStyle(color: AppColors.text3)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (final u in urls)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Image.network(
                AppConfig.resolveAssetUrl(u),
                fit: BoxFit.fitWidth,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  /// 合同来源菜单：上传 PDF 替换 / 切回平台模板（仅未锁定时可用）。
  void _openSourceMenu(ContractDetail? contract) {
    if (contract == null) return;
    if (!contract.isEditable) {
      showAppToast(context, '合同已进入签署，已锁定，不可修改');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('合同来源', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: AppColors.primary),
              title: Text(contract.isUploaded ? '重新上传合同 PDF' : '上传合同 PDF 替换模板'),
              onTap: () {
                Navigator.pop(ctx);
                _uploadSourcePdf(contract);
              },
            ),
            if (contract.isUploaded)
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
                title: const Text('切回平台模板'),
                onTap: () {
                  Navigator.pop(ctx);
                  _switchToTemplate(contract);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 上传 PDF 替换模板（选 PDF → 上传 → 清签并刷新）。
  Future<void> _uploadSourcePdf(ContractDetail contract) async {
    PickedFile? file;
    try {
      file = await NativeFilePicker.pickFile(
        filenamePrefix: 'contract',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } catch (e) {
      if (mounted) showAppToast(context, '$e');
      return;
    }
    if (file == null) return;
    final repo = ref.read(contractRepositoryProvider);
    try {
      await repo.uploadContractSourcePdf(
        contract.contractId,
        Uint8List.fromList(file.bytes),
        fileName: file.filename,
      );
      if (mounted) {
        showAppToast(context, '合同 PDF 已上传，可拖拽定位签署');
        _resetSignAndReload();
      }
    } catch (e) {
      if (mounted) showAppToast(context, '上传失败：$e');
    }
  }

  /// 从上传件切回平台模板（选模板 → 切换 → 清定位并刷新）。
  Future<void> _switchToTemplate(ContractDetail contract) async {
    final repo = ref.read(contractRepositoryProvider);
    List<ContractTemplate> templates;
    try {
      templates = await repo.listContractTemplates(contractId: contract.contractId);
    } catch (e) {
      if (mounted) showAppToast(context, '加载模板失败：$e');
      return;
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<ContractTemplate>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('选择平台模板', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final t in templates)
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
                title: Text(t.name),
                onTap: () => Navigator.pop(ctx, t),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await repo.switchContractToTemplate(contract.contractId, templateId: chosen.templateId);
      if (mounted) {
        showAppToast(context, '已切回平台模板');
        _resetSignAndReload();
      }
    } catch (e) {
      if (mounted) showAppToast(context, '切回失败：$e');
    }
  }

  /// 清空当前签名/印章/定位并重新加载合同（用于上传/切换后回到干净态）。
  void _resetSignAndReload() {
    setState(() {
      _signatureBytes = null;
      _signatureController.clear();
      _selectedSeal = null;
      _selectedSealBytes = null;
      _placements = [];
    });
    _loadedOrderId = null;
    ref.invalidate(contractByOrderProvider(widget.orderId));
  }

  /// 打开正文条款编辑底部弹窗（仅未锁定时可达）。
  Future<void> _openContentEditor(ContractDetail contract) async {
    final repo = ref.read(contractRepositoryProvider);
    List<ContractTemplate> templates;
    try {
      templates = await repo.listContractTemplates(contractId: contract.contractId);
    } catch (e) {
      if (mounted) showAppToast(context, '加载模板失败：$e');
      return;
    }
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ContractContentEditorSheet(
        contract: contract,
        templates: templates,
        repo: repo,
      ),
    );
    if (saved == true && mounted) {
      // 重新加载合同正文（HTML 随条款更新）
      _loadedOrderId = null;
      ref.invalidate(contractByOrderProvider(widget.orderId));
    }
  }

  /// 双签完成视图：展示已签署的合同内容（签名/印章已持久化在 HTML 中）+ PDF 入口
  Widget _buildCompletedView(ContractDetail contract) {
    final pdfUrl = contract.signedPdfUrl;
    return Column(
      children: [
        _buildStatusBar(contract),
        Expanded(child: contract.isUploaded ? _buildUploadedReadonly(contract) : _buildContractContent(contract)),
        if (pdfUrl != null && pdfUrl.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => _openSignedPdf(pdfUrl),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('查看签署完成 PDF'),
            ),
          ),
      ],
    );
  }

  /// 打开签署完成 PDF：/profile 为 root-relative，拼站点 origin；公开静态资源无需鉴权
  Future<void> _openSignedPdf(String pdfUrl) async {
    String full;
    try {
      full = '${Uri.parse(AppConfig.baseUrl).origin}$pdfUrl';
    } catch (_) {
      full = '${AppConfig.baseUrl}$pdfUrl';
    }
    final launched = await launchUrl(Uri.parse(full), mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showAppToast(context, '无法打开 PDF，请稍后重试');
    }
  }

  /// 签名区域：手写签名 + 使用印章
  Widget _buildSignatureArea() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('签署方式（可同时使用签名+盖章）',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text1)),
          const SizedBox(height: 12),
          // 手写签名
          Row(
            children: [
              Expanded(
                child: _buildOptionCard(
                  icon: Icons.edit_note,
                  title: '手写签名',
                  subtitle: _signatureBytes != null ? '已签名' : '点击绘制签名',
                  isSelected: _signatureBytes != null,
                  onTap: _openSignatureCanvas,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOptionCard(
                  icon: Icons.verified_user_outlined,
                  title: '使用印章',
                  subtitle: _selectedSeal != null ? _selectedSeal!.sealName : '点击选择印章',
                  isSelected: _selectedSeal != null,
                  onTap: _selectSeal,
                ),
              ),
            ],
          ),
          // 签名预览
          if (_signatureBytes != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('签名预览：', style: TextStyle(fontSize: 12, color: AppColors.text3)),
                const SizedBox(width: 8),
                Container(
                  height: 50,
                  width: 120,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Image.memory(_signatureBytes!, fit: BoxFit.contain),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _signatureBytes = null;
                      _signatureController.clear();
                    });
                  },
                  child: const Text('清除', style: TextStyle(fontSize: 12, color: AppColors.danger)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.05) : AppColors.fill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : AppColors.text3, size: 28),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: isSelected ? AppColors.primary : AppColors.text3),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  /// 印章预览
  Widget _buildSealPreview() {
    final sealUrl = _selectedSeal?.sealImageUrl ?? '';
    if (sealUrl.isEmpty) return const SizedBox.shrink();
    final fullUrl = AppConfig.resolveAssetUrl(sealUrl);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Text('印章预览：', style: TextStyle(fontSize: 12, color: AppColors.text3)),
          const SizedBox(width: 8),
          Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Image.network(fullUrl, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 24)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedSeal?.sealName ?? '', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text('审核状态：${_selectedSeal?.reviewStatusLabel ?? ''}',
                    style: const TextStyle(fontSize: 11, color: AppColors.text3)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _selectedSeal = null;
              _selectedSealBytes = null;
            }),
            child: const Text('移除', style: TextStyle(fontSize: 12, color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  /// 底部提交栏
  Widget _buildSubmitBar(ContractDetail contract) {
    final canSubmit = (_signatureBytes != null || _selectedSeal != null) && !_submitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('签署后不可撤销，请确认合同内容无误',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit ? () => _submitSign(contract) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('确认签署', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开全屏手写签名画布
  Future<void> _openSignatureCanvas() async {
    final controller = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 3,
    );

    final bytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 标题栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Text('手写签名', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        controller.clear();
                      },
                      child: const Text('清除', style: TextStyle(color: AppColors.danger)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (!controller.isNotEmpty) {
                          showAppToast(context, '请先绘制签名');
                          return;
                        }
                        final pngBytes = await controller.toPngBytes();
                        if (ctx.mounted) Navigator.pop(ctx, pngBytes);
                      },
                      child: const Text('完成', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 签名画布
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Signature(controller: controller),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (bytes != null) {
      setState(() {
        _signatureBytes = bytes;
      });
    }
  }

  /// 选择印章
  Future<void> _selectSeal() async {
    // 直接调用 repository 并 await，避免 ref.read(FutureProvider) 同步读到空数据
    final repo = ref.read(sealRepositoryProvider);
    final seals = await repo.mySeals();
    final approvedSeals = seals.where((s) => s.reviewStatus == 'approved' && s.sealStatus == 'enabled').toList();

    if (approvedSeals.isEmpty) {
      if (mounted) showAppToast(context, '暂无可用印章，请先上传并审核通过印章');
      return;
    }

    final selected = await showModalBottomSheet<SealItem>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('选择印章', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: approvedSeals.length,
                  itemBuilder: (_, i) {
                    final seal = approvedSeals[i];
                    return ListTile(
                      leading: const Icon(Icons.verified_user_outlined, color: AppColors.primary),
                      title: Text(seal.sealName, style: const TextStyle(fontSize: 14)),
                      subtitle: Text('审核状态：${seal.reviewStatusLabel}',
                          style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                      onTap: () => Navigator.pop(ctx, seal),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      // 选中即预下载印章图，提交时直接使用，避免慢网干等
      final sealBytes = await _downloadImage(selected.sealImageUrl);
      if (!mounted) return;
      if (sealBytes == null) {
        // 图片下载失败或不是合法图片（如印章源文件已被删）：不选中，给出明确提示
        showAppToast(context, '印章图片读取失败，请重新上传该印章');
        return;
      }
      setState(() {
        _selectedSeal = selected;
        _selectedSealBytes = sealBytes;
      });
    }
  }

  /// 提交签署
  Future<void> _submitSign(ContractDetail contract) async {
    // 二次确认
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('确认签署'),
        content: const Text('签署后不可撤销，请确认已仔细阅读合同内容。确定提交签署？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('再想想')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('确认签署', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    
    try {
      // 获取印章图片字节（选中时已预下载；为空则提交时兜底重试一次）
      Uint8List? sealBytes;
      if (_selectedSeal != null && _selectedSeal!.sealImageUrl.isNotEmpty) {
        sealBytes = _selectedSealBytes ?? await _downloadImage(_selectedSeal!.sealImageUrl);
        if (sealBytes == null) {
          // 选了印章但图片确实取不到（源文件丢失/非图片）：明确报错，不上传垃圾字节
          if (mounted) {
            showAppToast(context, '印章图片读取失败，请重新选择或上传印章');
            setState(() => _submitting = false);
          }
          return;
        }
      }
    
      // 客户端预校验：签名与印章至少一项，避免空提交后靠后端报错
      if (_signatureBytes == null && sealBytes == null) {
        if (mounted) {
          showAppToast(context, '请先手写签名或选择印章');
          setState(() => _submitting = false);
        }
        return;
      }
    
      // 上传件：必须已把签名/印章拖拽定位到页面，随签署一并提交 placements
      String? placementsJson;
      if (contract.isUploaded) {
        if (_placements.isEmpty) {
          if (mounted) {
            showAppToast(context, '请先将签名/印章拖动到合同页面');
            setState(() => _submitting = false);
          }
          return;
        }
        placementsJson = jsonEncode(_placements);
      }

      final contractRepo = ref.read(contractRepositoryProvider);
      await contractRepo.signContract(
        contract.contractId,
        signatureImage: _signatureBytes,
        sealImage: sealBytes,
        placements: placementsJson,
      );

      if (mounted) {
        showAppToast(context, '签署成功');
        // 刷新合同缓存
        ref.invalidate(contractByOrderProvider(widget.orderId));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '签署失败：$e');
        setState(() => _submitting = false);
      }
    }
  }

  /// 下载图片为字节（公开静态资源，不带鉴权头）。
  ///
  /// 为什么不能用带 token 的 apiClient：/profile/** 是匿名可访问的静态资源，
  /// 一旦携带 APP 域 Bearer 头，后端安全过滤器校验该 token 失败会返回 403，
  /// 于是把 403 错误体当成印章字节上传，最终报「格式不支持」。
  Future<Uint8List?> _downloadImage(String url) async {
    try {
      if (url.isEmpty) return null;
      // 归一为当前后端 origin（相对路径 / 其他 host 的绝对地址均按 /profile/ 锚点重拼）。
      final assetUrl = AppConfig.resolveAssetUrl(url);
      final bytes = await _fetchPublicUrl(assetUrl);
      if (bytes == null || !_looksLikeImage(bytes)) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 无鉴权裸下载：临时 Dio 实例，不挂 AuthInterceptor、不注入 Authorization 头。
  Future<Uint8List?> _fetchPublicUrl(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      responseType: ResponseType.bytes,
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ));
    try {
      final resp = await dio.get<Uint8List>(url);
      final data = resp.data;
      return data == null ? null : Uint8List.fromList(data);
    } catch (_) {
      return null;
    } finally {
      dio.close(force: true);
    }
  }

  /// 魔数嗅探：仅当字节头匹配 png/jpg/gif/bmp/webp 才认作图片，
  /// 避免把 403/404 错误体当印章上传导致后端报「格式不支持」的误导性错误。
  bool _looksLikeImage(Uint8List b) {
    if (b.length < 4) return false;
    // PNG: 89 50 4E 47
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true;
    // JPEG: FF D8 FF
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
    // GIF: 47 49 46 38 ('GIF8')
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return true;
    // BMP: 42 4D ('BM')
    if (b[0] == 0x42 && b[1] == 0x4D) return true;
    // WEBP: RIFF....WEBP
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return true;
    return false;
  }
}

/// 上传 PDF 分页拖拽定位层。
///
/// 服务端已将上传合同逐页渲染为公开静态图（/profile/.../page_{i}.png），
/// 本组件按页展示图片，并把当前方的签名（Image.memory）与印章（Image.network）
/// 作为可拖动/缩放的浮块叠在页面上；坐标以页面比例 (0..1) 维护，切页保留。
/// 签名/印章各一枚，出现即默认落在当前页、消失即移除；变更通过 [onPlacementsChanged]
/// 回传（不触发父级 setState，避免重建环）。
class _PdfPlacementViewer extends StatefulWidget {
  const _PdfPlacementViewer({
    required this.pageImageUrls,
    required this.signatureBytes,
    required this.sealFullUrl,
    required this.onPlacementsChanged,
  });

  final List<String> pageImageUrls;
  final Uint8List? signatureBytes;
  final String? sealFullUrl;
  final void Function(List<Map<String, dynamic>> placements) onPlacementsChanged;

  @override
  State<_PdfPlacementViewer> createState() => _PdfPlacementViewerState();
}

class _PdfPlacementViewerState extends State<_PdfPlacementViewer> {
  static const double _minW = 0.03;

  int _page = 0;
  String? _selectedKind;
  final List<_PlacementChip> _chips = [];
  // 页面图固有宽高比缓存（键为解析后的完整 URL）：用于按页面真实比例等比展示，
  // 消除 BoxFit.fill 的非等比拉伸，并保证浮块纵向尺寸与后端按图片宽高比换算一致。
  final Map<String, double> _aspectByUrl = {};
  final Set<String> _pendingAspect = {};

  @override
  void initState() {
    super.initState();
    _syncChips();
    // 默认浮块落位后立即回传父层，保证用户不拖动直接提交时 _placements 非空；
    // initState 处于 build 阶段，直接回调会触发祖先 setState 报错，故延到帧后。
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void didUpdateWidget(covariant _PdfPlacementViewer old) {
    super.didUpdateWidget(old);
    final sigChanged = old.signatureBytes != widget.signatureBytes;
    final sealChanged = old.sealFullUrl != widget.sealFullUrl;
    if (sigChanged || sealChanged) {
      _syncChips();
      _emit();
    }
  }

  /// 依据当前签名/印章是否存在，增删对应定位浮块（各一枚）。
  void _syncChips() {
    _ensureChip('signature', widget.signatureBytes != null, _PlacementChip(
        kind: 'signature', page: 0, x: 0.08, y: 0.72, w: 0.28));
    _ensureChip('seal', widget.sealFullUrl != null && widget.sealFullUrl!.isNotEmpty,
        _PlacementChip(kind: 'seal', page: 0, x: 0.6, y: 0.68, w: 0.2));
    if (_page >= widget.pageImageUrls.length) {
      _page = widget.pageImageUrls.isEmpty ? 0 : widget.pageImageUrls.length - 1;
    }
  }

  void _ensureChip(String kind, bool shouldExist, _PlacementChip defaultChip) {
    final idx = _chips.indexWhere((c) => c.kind == kind);
    if (shouldExist && idx < 0) {
      _chips.add(defaultChip.copyWith(page: _page));
    } else if (!shouldExist && idx >= 0) {
      _chips.removeAt(idx);
    }
  }

  void _emit() {
    widget.onPlacementsChanged(_chips
        .map((c) => {
              'kind': c.kind,
              'page': c.page,
              'x': _r4(c.x),
              'y': _r4(c.y),
              'w': _r4(c.w),
            })
        .toList());
  }

  static double _r4(double v) => (v * 10000).roundToDouble() / 10000;
  static double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  _PlacementChip? get _selected {
    for (final c in _chips) {
      if (c.kind == _selectedKind) return c;
    }
    return null;
  }

  /// 解析当前页图片固有尺寸得到宽高比，驱动等比展示；未就绪前保持空（回退为拉伸，仅首帧瞬态）。
  void _ensurePageAspect() {
    if (widget.pageImageUrls.isEmpty || _page >= widget.pageImageUrls.length) {
      return;
    }
    final url = AppConfig.resolveAssetUrl(widget.pageImageUrls[_page]);
    if (_aspectByUrl.containsKey(url) || _pendingAspect.contains(url)) {
      return;
    }
    _pendingAspect.add(url);
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      _pendingAspect.remove(url);
      if (!mounted) return;
      final h = info.image.height;
      if (h > 0) {
        setState(() => _aspectByUrl[url] = info.image.width / h);
      }
      stream.removeListener(listener);
    }, onError: (e, s) {
      _pendingAspect.remove(url);
    });
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.pageImageUrls;
    if (pages.isEmpty) {
      return const Center(
          child: Text('上传合同无可预览页面',
              style: TextStyle(color: AppColors.text3)));
    }
    if (_page >= pages.length) _page = pages.length - 1;
    if (_page < 0) _page = 0;
    _ensurePageAspect();
    final currentUrl = AppConfig.resolveAssetUrl(pages[_page]);
    final aspect = _aspectByUrl[currentUrl];

    return Column(
      children: [
        // 翻页工具条 + 拖拽提示
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _page > 0
                    ? () => setState(() => _page--)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text('第 ${_page + 1} / ${pages.length} 页 · 拖动定位，右下角缩放，点击选中可跨页移动',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _page < pages.length - 1
                    ? () => setState(() => _page++)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LayoutBuilder(builder: (context, outer) {
                // 按页面真实宽高比等比内缩（letterbox），使显示区宽高比 == 页面宽高比，
                // BoxFit.fill 因此不再拉伸页面图，浮块纵向尺寸也与后端换算一致（缺陷 #4）。
                double innerW = outer.maxWidth;
                double innerH = outer.maxHeight;
                if (aspect != null && aspect > 0) {
                  if (innerW / innerH > aspect) {
                    innerW = innerH * aspect;
                  } else {
                    innerH = innerW / aspect;
                  }
                }
                return Center(
                  child: SizedBox(
                    width: innerW,
                    height: innerH,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          currentUrl,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              Container(color: AppColors.fill),
                        ),
                        // 当前页的每个浮块
                        for (final chip in _chips)
                          if (chip.page == _page)
                            _buildChipWidget(chip, innerW, innerH),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        _buildSelectionBar(),
      ],
    );
  }

  /// 选中浮块后的跨页操作栏：将选中的签名/印章移到当前查看页（缺陷 #3）。
  Widget _buildSelectionBar() {
    final sel = _selected;
    if (sel == null) return const SizedBox.shrink();
    final onCurrent = sel.page == _page;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.touch_app_outlined, size: 16, color: AppColors.text2),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '已选中${sel.kind == 'signature' ? '签名' : '印章'}（第 ${sel.page + 1} 页）',
              style: const TextStyle(fontSize: 12, color: AppColors.text2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!onCurrent)
            TextButton.icon(
              onPressed: () {
                setState(() => sel.page = _page);
                _emit();
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('移到当前页'),
            ),
          TextButton(
            onPressed: () => setState(() => _selectedKind = null),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildChipWidget(_PlacementChip chip, double boxW, double boxH) {
    final chipWPx = _clamp(chip.w * boxW, 24, boxW);
    final left = _clamp(chip.x * boxW, 0, boxW - chipWPx);
    final top = _clamp(chip.y * boxH, 0, boxH * 0.99);
    final isSignature = chip.kind == 'signature';
    final selected = chip.kind == _selectedKind;

    final image = isSignature
        ? (widget.signatureBytes == null
            ? const SizedBox.shrink()
            : Image.memory(widget.signatureBytes!, fit: BoxFit.contain))
        : (widget.sealFullUrl == null
            ? const SizedBox.shrink()
            : Image.network(widget.sealFullUrl!, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()));

    return Positioned(
      left: left,
      top: top,
      width: chipWPx,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () =>
            setState(() => _selectedKind = selected ? null : chip.kind),
        onPanUpdate: (d) {
          setState(() {
            chip.x = _clamp(chip.x + d.delta.dx / boxW, 0, 1 - chip.w);
            chip.y = _clamp(chip.y + d.delta.dy / boxH, 0, 0.99);
          });
          _emit();
        },
        onPanEnd: (_) => _emit(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: isSignature ? AppColors.primary : AppColors.danger,
                    width: selected ? 2.5 : 1),
                color: selected ? Colors.black.withOpacity(0.06) : Colors.transparent,
              ),
              child: image,
            ),
            // 右下角缩放手柄
            Positioned(
              right: -8,
              bottom: -8,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  setState(() {
                    chip.w = _clamp(chip.w + d.delta.dx / boxW, _minW, 1 - chip.x);
                  });
                  _emit();
                },
                onPanEnd: (_) => _emit(),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isSignature ? AppColors.primary : AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个签章定位浮块（比例坐标）：x/y 为左上角相对页面，w 为宽度比例。
class _PlacementChip {
  _PlacementChip({
    required this.kind,
    required this.page,
    required this.x,
    required this.y,
    required this.w,
  });

  final String kind;
  int page;
  double x;
  double y;
  double w;

  _PlacementChip copyWith({int? page}) => _PlacementChip(
        kind: kind,
        page: page ?? this.page,
        x: x,
        y: y,
        w: w,
      );
}

/// 合同正文条款编辑底部弹窗：模板下拉 + 多行条款输入 + 保存。
class _ContractContentEditorSheet extends StatefulWidget {
  const _ContractContentEditorSheet({
    required this.contract,
    required this.templates,
    required this.repo,
  });

  final ContractDetail contract;
  final List<ContractTemplate> templates;
  final ContractRepository repo;

  @override
  State<_ContractContentEditorSheet> createState() =>
      _ContractContentEditorSheetState();
}

class _ContractContentEditorSheetState
    extends State<_ContractContentEditorSheet> {
  late String _templateId;
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _templateId = widget.contract.templateId?.trim().isNotEmpty == true
        ? widget.contract.templateId!
        : (widget.templates.isNotEmpty ? widget.templates.first.templateId : '');
    _controller = TextEditingController(text: widget.contract.clausesText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _defaultFor(String templateId) {
    for (final t in widget.templates) {
      if (t.templateId == templateId) return t.defaultClausesText;
    }
    return '';
  }

  void _onTemplateChanged(String tid) {
    setState(() {
      _templateId = tid;
      _controller.text = _defaultFor(tid);
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      showAppToast(context, '合同正文条款不能为空');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.repo.updateContractContent(
        widget.contract.contractId,
        templateId: _templateId,
        clausesText: text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // 锁定/非法参数：后端 message 直接弹提示，保持弹窗供用户修改
      if (mounted) {
        showAppToast(context, '$e');
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('编辑合同内容',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 12),
            const Text('平台模板',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _templateId.isEmpty ? null : _templateId,
              isExpanded: true,
              items: widget.templates
                  .map((t) =>
                      DropdownMenuItem(value: t.templateId, child: Text(t.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _onTemplateChanged(v);
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),
            const Text('正文条款（第一条~第六条，可自由修改；切换模板将填充默认条款）',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
            const SizedBox(height: 6),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 14, height: 1.6),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                  hintText: '请输入合同正文条款',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
