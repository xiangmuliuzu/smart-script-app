import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'seal_models.dart';

/// 印章数据仓库（App 端用户侧）。
class SealRepository {
  SealRepository(this._api);

  final ApiClient _api;

  /// 我的印章列表。
  Future<List<SealItem>> mySeals() async {
    final data = await _api.get<List<dynamic>>(
      '/content/copyright-seals',
    );
    if (data == null) return const [];
    return data
        .whereType<Map>()
        .map((e) => SealItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 印章详情（含材料、日志）。
  Future<SealDetail?> sealDetail(int sealId) async {
    try {
      final data = await _api.get<Map<String, dynamic>>(
        '/content/copyright-seals/$sealId',
      );
      if (data == null) return null;
      return SealDetail.fromJson(data);
    } on ApiException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  /// 上传印章图片（首次提交）。
  Future<int> submitSeal({
    required String sealName,
    required String sealImageUrl,
    String? materialUrls,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/content/copyright-seals',
      data: <String, dynamic>{
        'sealName': sealName,
        'sealImageUrl': sealImageUrl,
        'materialUrls': materialUrls ?? '',
      },
    );
    return (data?['sealId'] as num?)?.toInt() ?? 0;
  }

  /// 补充审核材料。
  Future<void> addMaterials({
    required int sealId,
    required String additionalMaterialUrls,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/content/copyright-seals/$sealId/materials',
      data: <String, dynamic>{
        'additionalMaterialUrls': additionalMaterialUrls,
      },
    );
  }

  /// 重新提交印章（驳回后重新上传）。
  Future<void> resubmitSeal({
    required int sealId,
    required String sealImageUrl,
    String? materialUrls,
  }) async {
    await _api.put<Map<String, dynamic>>(
      '/content/copyright-seals/$sealId/resubmit',
      data: <String, dynamic>{
        'sealImageUrl': sealImageUrl,
        'materialUrls': materialUrls ?? '',
      },
    );
  }

  /// 停用印章。
  Future<void> disableSeal(int sealId) async {
    await _api.put<Map<String, dynamic>>(
      '/content/copyright-seals/$sealId/disable',
    );
  }

  /// 更新印章信息（编辑印章名称、图片、材料，修改后重置审核状态为 pending）。
  Future<void> updateSeal({
    required int sealId,
    String? sealName,
    String? sealImageUrl,
    String? materialUrls,
  }) async {
    final body = <String, String>{};
    if (sealName != null) body['sealName'] = sealName;
    if (sealImageUrl != null) body['sealImageUrl'] = sealImageUrl;
    if (materialUrls != null) body['materialUrls'] = materialUrls;

    await _api.put<Map<String, dynamic>>(
      '/content/copyright-seals/$sealId',
      data: body,
    );
  }

  /// 删除印章（软删除）。
  Future<void> deleteSeal(int sealId) async {
    await _api.delete<Map<String, dynamic>>(
      '/content/copyright-seals/$sealId',
    );
  }

  /// 上传审核材料（支持图片和文档）。
  Future<String> uploadMaterial({
    required List<int> bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'type': 'material', // 使用默认白名单（图片+文档）
    });
    
    final data = await _api.upload<Map<String, dynamic>>(
      '/content/upload',
      formData: formData,
    );
    
    final url = data?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw ApiException('材料上传失败，请稍后重试');
    }
    return url;
  }
}
