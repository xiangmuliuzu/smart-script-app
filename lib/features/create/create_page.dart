import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_page.dart';

/// 创作/上传（底部中间"+"，接口文档 2.9）——占位，待上传创作负责人实现。
class CreatePage extends StatelessWidget {
  const CreatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(title: '创作', subtitle: '剧本上传 / AI 写作 / AI 润色 / 草稿箱');
  }
}
