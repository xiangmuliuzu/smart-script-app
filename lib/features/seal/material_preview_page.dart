import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../core/theme/app_colors.dart';

/// 材料预览页面（支持图片、文本和文档在线预览）。
///
/// 功能：
/// 1. 图片：使用 Image.network 直接显示
/// 2. 纯文本（.txt）：下载后直接显示文本内容
/// 3. PDF/Word/Excel 等文档：使用 WebView 通过在线文档预览服务显示
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
  late final WebViewController? _webViewController;
  bool _isLoading = true;
  String? _errorMessage;
  String? _textContent; // 用于存储纯文本内容

  @override
  void initState() {
    super.initState();
    
    // 判断文件类型
    if (_isImageUrl(widget.materialUrl)) {
      _webViewController = null;
      _isLoading = false;
    } else if (_isTextUrl(widget.materialUrl)) {
      _webViewController = null;
      _loadTextContent();
    } else {
      // 文档类型使用 WebView 加载
      _initWebView();
    }
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            setState(() {
              _isLoading = false;
              _errorMessage = '加载失败: ${error.description}';
            });
          },
        ),
      )
      // 使用 Google Docs Viewer 预览文档
      ..loadRequest(Uri.parse(
        'https://docs.google.com/viewer?url=${Uri.encodeComponent(widget.materialUrl)}&embedded=true',
      ));
  }

  /// 加载纯文本内容
  Future<void> _loadTextContent() async {
    try {
      final response = await http.get(Uri.parse(widget.materialUrl));
      
      if (response.statusCode == 200) {
        // 尝试使用 UTF-8 解码
        String content;
        try {
          content = utf8.decode(response.bodyBytes);
        } catch (e) {
          // 如果 UTF-8 失败，尝试使用 Latin1
          content = latin1.decode(response.bodyBytes);
        }
        
        setState(() {
          _textContent = content;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '加载失败: HTTP ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 按 URL 或材料文件名判断类型（上传路径可能带随机前缀，文件名更可靠）。
  bool _isImageUrl(String url) {
    return _hasExt(url, const ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp']) ||
        _hasExt(widget.materialName, const ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp']);
  }

  bool _isTextUrl(String url) {
    return _hasExt(url, const ['.txt']) || _hasExt(widget.materialName, const ['.txt']);
  }

  bool _hasExt(String value, List<String> exts) {
    final lower = value.toLowerCase().split('?').first;
    return exts.any(lower.endsWith);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.materialName,
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isImageUrl(widget.materialUrl)) {
      return _buildImagePreview();
    } else if (_isTextUrl(widget.materialUrl)) {
      return _buildTextPreview();
    } else {
      return _buildDocumentPreview();
    }
  }

  /// 图片预览（支持缩放）。
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.white54),
                  const SizedBox(height: 16),
                  const Text(
                    '图片加载失败',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 纯文本预览。
  Widget _buildTextPreview() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _loadTextContent();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
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
    );
  }

  /// 文档预览（使用 WebView）。
  Widget _buildDocumentPreview() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _initWebView();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        if (_webViewController != null)
          WebViewWidget(controller: _webViewController!),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
      ],
    );
  }
}
