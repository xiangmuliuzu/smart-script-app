import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';

/// 材料预览页面（支持图片、文本；PDF 直链 WebView；Office 引导本地下载）。
///
/// 说明：
/// - TXT：兼容 UTF-8 / UTF-16（Windows 记事本常见），避免按 UTF-8 硬解导致乱码；
/// - Office：不再走 Google Docs Viewer（内网 /profile 地址无法被 Google 拉取，会黑屏），
///   与 Admin / User Web 一致，提示下载后用本地软件打开。
class MaterialPreviewPage extends StatefulWidget {
  const MaterialPreviewPage({
    super.key,
    required this.materialUrl,
    required this.materialName,
  });

  final String materialUrl;
  final String materialName;

  @override
  State<MaterialPreviewPage> createState() => _MaterialPreviewPageState();
}

class _MaterialPreviewPageState extends State<MaterialPreviewPage> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  String? _errorMessage;
  String? _textContent;

  @override
  void initState() {
    super.initState();
    if (_isImage) {
      _isLoading = false;
    } else if (_isText) {
      _loadTextContent();
    } else if (_isPdf) {
      _initPdfWebView();
    } else {
      // Office / 其它：不加载 WebView，直接展示引导页
      _isLoading = false;
    }
  }

  bool get _isImage =>
      _hasExt(widget.materialUrl, _imageExts) ||
      _hasExt(widget.materialName, _imageExts);

  bool get _isText =>
      _hasExt(widget.materialUrl, _textExts) ||
      _hasExt(widget.materialName, _textExts);

  bool get _isPdf =>
      _hasExt(widget.materialUrl, const ['.pdf']) ||
      _hasExt(widget.materialName, const ['.pdf']);

  bool get _isOffice =>
      _hasExt(widget.materialUrl, _officeExts) ||
      _hasExt(widget.materialName, _officeExts);

  static const _imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
  static const _textExts = ['.txt', '.md', '.csv', '.log', '.json'];
  static const _officeExts = [
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
  ];

  bool _hasExt(String value, List<String> exts) {
    final lower = value.toLowerCase().split('?').first;
    return exts.any(lower.endsWith);
  }

  void _initPdfWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = 'PDF 加载失败，可尝试在浏览器中打开';
            });
          },
        ),
      )
      // 直接加载文件地址（系统 WebView 可渲染 PDF）；不使用 Google Docs（无法访问内网）
      ..loadRequest(Uri.parse(widget.materialUrl));
    _webViewController = controller;
  }

  /// 加载纯文本：按 BOM / 试探解码，兼容记事本 UTF-16。
  Future<void> _loadTextContent() async {
    try {
      final response = await http.get(Uri.parse(widget.materialUrl));
      if (response.statusCode != 200) {
        setState(() {
          _errorMessage = '加载失败: HTTP ${response.statusCode}';
          _isLoading = false;
        });
        return;
      }
      // 后端偶发返回 JSON 错误体（如 401 包装）
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        setState(() {
          _errorMessage = '材料地址无效或无权限，请稍后重试';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _textContent = decodeMaterialText(response.bodyBytes);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.materialUrl);
    if (uri == null) {
      setState(() => _errorMessage = '无效的文件地址');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开文件，请检查是否已安装对应应用')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkChrome = _isImage || (_isPdf && _errorMessage == null && !_isOffice);
    return Scaffold(
      backgroundColor: darkChrome ? Colors.black : AppColors.pageBackground,
      appBar: AppBar(
        title: Text(widget.materialName, style: const TextStyle(fontSize: 16)),
        backgroundColor: darkChrome ? Colors.black87 : Colors.white,
        foregroundColor: darkChrome ? Colors.white : Colors.black,
        elevation: 0.5,
        actions: [
          if (_isOffice || _isPdf)
            TextButton(
              onPressed: _openExternally,
              child: Text(
                '打开',
                style: TextStyle(
                  color: darkChrome ? Colors.white : AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isImage) return _buildImagePreview();
    if (_isText) return _buildTextPreview();
    if (_isPdf) return _buildPdfPreview();
    return _buildOfficeFallback();
  }

  Widget _buildImagePreview() {
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.network(
          widget.materialUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: Colors.white,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.white54),
                  SizedBox(height: 16),
                  Text('图片加载失败', style: TextStyle(color: Colors.white70)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextPreview() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _errorView(
        onRetry: () {
          setState(() {
            _errorMessage = null;
            _isLoading = true;
          });
          _loadTextContent();
        },
      );
    }
    return ColoredBox(
      color: Colors.white,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _textContent ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPdfPreview() {
    if (_errorMessage != null) {
      return _errorView(
        onRetry: () {
          setState(() {
            _errorMessage = null;
            _isLoading = true;
          });
          _initPdfWebView();
        },
        extraAction: TextButton(
          onPressed: _openExternally,
          child: const Text('在浏览器中打开'),
        ),
      );
    }
    return Stack(
      children: [
        if (_webViewController != null)
          WebViewWidget(controller: _webViewController!),
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }

  /// Office 等：对齐 Admin，不内嵌预览，引导外部打开。
  Widget _buildOfficeFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 64, color: AppColors.text3),
            const SizedBox(height: 16),
            Text(
              _isOffice
                  ? '该 Office 文档暂不支持 App 内预览'
                  : '该文件格式暂不支持在线预览',
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.text1,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '请下载后使用手机上的 WPS / Office 等应用打开。',
              style: TextStyle(fontSize: 14, color: AppColors.text3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openExternally,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('打开 / 下载文件'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView({required VoidCallback onRetry, Widget? extraAction}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.text3),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? '加载失败',
              style: const TextStyle(color: AppColors.text2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
            if (extraAction != null) ...[
              const SizedBox(height: 8),
              extraAction,
            ],
          ],
        ),
      ),
    );
  }
}

/// 解码材料文本字节：UTF-16 LE/BE（含 BOM）、UTF-8。
String decodeMaterialText(List<int> raw) {
  final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
  if (bytes.isEmpty) return '';

  // UTF-16 LE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes, littleEndian: true, skipBom: true);
  }
  // UTF-16 BE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes, littleEndian: false, skipBom: true);
  }
  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }

  final asUtf8 = utf8.decode(bytes, allowMalformed: true);
  // 若几乎全是替换符，且长度为偶数，再试 UTF-16 LE（无 BOM 的记事本少见，但可兜底）
  final replacementCount = '\uFFFD'.allMatches(asUtf8).length;
  if (replacementCount > 0 &&
      bytes.length.isEven &&
      replacementCount >= (asUtf8.length / 4).ceil()) {
    final asUtf16 = _decodeUtf16(bytes, littleEndian: true, skipBom: false);
    if (!asUtf16.contains('\uFFFD') && asUtf16.trim().isNotEmpty) {
      return asUtf16;
    }
  }
  return asUtf8;
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  required bool skipBom,
}) {
  var offset = skipBom ? 2 : 0;
  if ((bytes.length - offset).isOdd) {
    // 截断损坏尾字节，避免越界
  }
  final codeUnits = <int>[];
  for (var i = offset; i + 1 < bytes.length; i += 2) {
    final unit = littleEndian
        ? (bytes[i] | (bytes[i + 1] << 8))
        : ((bytes[i] << 8) | bytes[i + 1]);
    codeUnits.add(unit);
  }
  return String.fromCharCodes(codeUnits);
}
