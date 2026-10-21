/// 版权材料预览：复用印章模块预览能力，并正确解析相对资源地址。
library;

import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../seal/material_preview_page.dart' as seal;

/// 图片查看器页面（相对路径会经 [AppConfig.resolveAssetUrl] 归一）。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.imageUrl,
    this.title,
  });

  final String imageUrl;
  final String? title;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _controller.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = AppConfig.resolveAssetUrl(widget.imageUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.title != null
            ? Text(
                widget.title!,
                style: const TextStyle(color: Colors.white),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetZoom,
            tooltip: '重置缩放',
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            resolvedUrl,
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image, size: 64, color: Colors.white54),
                    SizedBox(height: 16),
                    Text(
                      '图片加载失败',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 材料预览页面（图片 / txt / PDF 等，与印章审核一致）。
///
/// 后端上传返回的是相对路径 `/profile/upload/...`，必须先
/// [AppConfig.resolveAssetUrl] 再交给预览页，否则 Image.network 会直接失败。
class MaterialPreviewPage extends StatelessWidget {
  const MaterialPreviewPage({
    super.key,
    required this.url,
    required this.filename,
    required this.fileType,
  });

  final String url;
  final String filename;
  final String fileType;

  @override
  Widget build(BuildContext context) {
    return seal.MaterialPreviewPage(
      materialUrl: AppConfig.resolveAssetUrl(url),
      materialName: _previewName(filename, fileType),
    );
  }

  /// 预览类型优先看文件名扩展名；缺失时用 fileType 兜底，供印章预览页识别。
  static String _previewName(String filename, String fileType) {
    if (filename.trim().isNotEmpty) return filename;
    switch (fileType) {
      case 'image':
        return 'image.png';
      case 'pdf':
        return 'document.pdf';
      case 'document':
        return 'document.txt';
      default:
        return '材料预览';
    }
  }
}
