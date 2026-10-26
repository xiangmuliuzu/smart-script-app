import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../seal/data/seal_models.dart';
import '../../seal/data/seal_providers.dart';
import '../data/contract_providers.dart';
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
          if (_loadedOrderId != widget.orderId) {
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
              Expanded(child: _buildContractContent(contract)),
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

  /// 双签完成视图：展示已签署的合同内容（签名/印章已持久化在 HTML 中）+ PDF 入口
  Widget _buildCompletedView(ContractDetail contract) {
    final pdfUrl = contract.signedPdfUrl;
    return Column(
      children: [
        _buildStatusBar(contract),
        Expanded(child: _buildContractContent(contract)),
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
    
      final contractRepo = ref.read(contractRepositoryProvider);
      await contractRepo.signContract(
        contract.contractId,
        signatureImage: _signatureBytes,
        sealImage: sealBytes,
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
