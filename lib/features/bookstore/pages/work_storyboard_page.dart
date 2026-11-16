import 'package:flutter/material.dart';

import '../../../shared/widgets/common_views.dart';

/// 作品分镜目录（占位页）。
///
/// 入口位置：作品详情页「章节目录」下方，仅当当前用户在这本书下已有分镜成果时展示。
/// 预留契约（由后续接入方实现，页面签名保持不变）：
///   GET /content/works/{workId}/storyboards/summary
///   GET /content/works/{workId}/storyboards?pageNum=&pageSize=
/// 数据范围：仅当前登录用户本人的分镜记录（user_id = 当前用户）。
class WorkStoryboardPage extends StatelessWidget {
  const WorkStoryboardPage({super.key, required this.workId, this.title});

  final int workId;

  /// 作品标题，仅用于页面标题展示。
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text((title == null || title!.isEmpty) ? '分镜目录' : '${title!} · 分镜目录'),
      ),
      body: const EmptyView(
        message: '分镜目录正在接入',
        icon: Icons.movie_filter_outlined,
      ),
    );
  }
}
