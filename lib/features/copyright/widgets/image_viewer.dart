/// 图片查看器组件（支持缩放、手势）
library;

import 'package:flutter/material.dart';

/// 图片查看器页面
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
            widget.imageUrl,
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

/// 材料预览页面（支持图片和 PDF）
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

  bool get isImage =>
      fileType == 'image' ||
      filename.toLowerCase().endsWith('.jpg') ||
      filename.toLowerCase().endsWith('.jpeg') ||
      filename.toLowerCase().endsWith('.png');

  bool get isPdf => fileType == 'pdf' || filename.toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    if (isImage) {
      return ImageViewerPage(imageUrl: url, title: filename);
    }

    // 非图片文件类型：提示无法预览
    return Scaffold(
      appBar: AppBar(
        title: Text(filename),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                size: 80,
                color: Colors.grey,
              ),
              const SizedBox(height: 24),
              Text(
                filename,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                isPdf ? 'PDF文件暂不支持在线预览' : '该文件类型暂不支持在线预览',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '您可以通过其他方式下载查看',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
