import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_page.dart';

/// 漫剧（接口文档 2.8）——占位，待漫剧负责人实现。
class ComicPage extends StatelessWidget {
  const ComicPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(title: '漫剧', subtitle: '短剧信息流 / 播放 / 解锁 / 评论');
  }
}
