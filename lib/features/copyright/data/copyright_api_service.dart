/// 版权管理 API 服务（App 端）。
///
/// 接口基础路径: /api/v1/content/copyright
library;

import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import 'copyright_models.dart';

class CopyrightApiService {
  final ApiClient _client;

  CopyrightApiService(this._client);

  // ==================== 版权申请 ====================

  /// 获取我的版权申请列表
  ///
  /// GET /content/copyright/application/list
  /// 查询参数: pageNum, pageSize, status, workName
  Future<Map<String, dynamic>> getMyApplications({
    int pageNum = 1,
    int pageSize = 10,
    String? status,
    String? workName,
  }) async {
    final params = <String, dynamic>{
      'pageNum': pageNum,
      'pageSize': pageSize,
    };
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (workName != null && workName.isNotEmpty) params['workName'] = workName;

    final data = await _client.get(
      '/content/copyright/application/list',
      query: params,
    );

    return {
      'total': data['total'] ?? 0,
      'rows': (data['rows'] as List?)
              ?.map((e) => CopyrightApplication.fromJson(e))
              .toList() ??
          <CopyrightApplication>[],
    };
  }

  /// 获取版权申请详情
  ///
  /// GET /content/copyright/application/{id}
  Future<CopyrightApplication> getApplicationDetail(int applyId) async {
    final data = await _client.get(
      '/content/copyright/application/$applyId',
    );

    return CopyrightApplication.fromJson(data);
  }

  /// 提交版权申请
  ///
  /// POST /content/copyright/application/apply
  Future<bool> submitApplication(CopyrightApplyDTO dto) async {
    await _client.post(
      '/content/copyright/application/apply',
      data: dto.toJson(),
    );

    return true;
  }

  /// 重新提交版权申请（驳回后）
  ///
  /// POST /content/copyright/application/resubmit
  Future<bool> resubmitApplication(CopyrightResubmitDTO dto) async {
    await _client.post(
      '/content/copyright/application/resubmit',
      data: dto.toJson(),
    );

    return true;
  }

  /// 删除版权申请（仅限pending状态）
  ///
  /// DELETE /content/copyright/application/{id}
  Future<bool> deleteApplication(int applyId) async {
    await _client.delete(
      '/content/copyright/application/$applyId',
    );

    return true;
  }

  /// 更新版权申请（仅限pending状态）
  ///
  /// PUT /content/copyright/application/{id}
  Future<bool> updateApplication(int applyId, CopyrightApplyDTO dto) async {
    await _client.put(
      '/content/copyright/application/$applyId',
      data: dto.toJson(),
    );

    return true;
  }

  // ==================== 版权证书 ====================

  /// 获取我的版权证书列表
  ///
  /// GET /content/copyright/cert/list
  /// 查询参数: pageNum, pageSize, workName
  Future<Map<String, dynamic>> getMyCertificates({
    int pageNum = 1,
    int pageSize = 10,
    String? workName,
  }) async {
    final params = <String, dynamic>{
      'pageNum': pageNum,
      'pageSize': pageSize,
    };
    if (workName != null && workName.isNotEmpty) params['workName'] = workName;

    final data = await _client.get(
      '/content/copyright/cert/list',
      query: params,
    );

    return {
      'total': data['total'] ?? 0,
      'rows': (data['rows'] as List?)
              ?.map((e) => CopyrightCert.fromJson(e))
              .toList() ??
          <CopyrightCert>[],
    };
  }

  /// 获取版权证书详情
  ///
  /// GET /content/copyright/cert/{id}
  Future<CopyrightCert> getCertificateDetail(int certId) async {
    final data = await _client.get(
      '/content/copyright/cert/$certId',
    );

    return CopyrightCert.fromJson(data);
  }

  /// 下载版权证书 PDF
  ///
  /// GET /content/copyright/cert/{id}/download
  /// 返回文件 URL 或直接下载流
  Future<String> downloadCertificatePdf(int certId) async {
    final data = await _client.get(
      '/content/copyright/cert/$certId/download',
    );

    // 后端可能直接返回文件 URL，或者返回 {url: "..."}
    if (data is String) {
      return data;
    }
    return data['url'] ?? '';
  }

  // ==================== 版权中心配置 ====================

  /// 获取可用的版权中心列表
  ///
  /// GET /content/copyright/config/active
  Future<List<CopyrightCenter>> getActiveCenters() async {
    final data = await _client.get(
      '/content/copyright/config/active',
    );

    return (data as List?)
            ?.map((e) => CopyrightCenter.fromJson(e))
            .toList() ??
        <CopyrightCenter>[];
  }

  // ==================== 辅助：获取我的作品列表（用于申请时选择）====================

  /// 获取我的作品列表（简要信息）
  ///
  /// GET /content/works/my-list
  Future<List<MyWorkBrief>> getMyWorks() async {
    final data = await _client.get(
      '/content/works/my-list',
    );

    return (data as List?)
            ?.map((e) => MyWorkBrief.fromJson(e))
            .toList() ??
        <MyWorkBrief>[];
  }

  // ==================== 文件上传 ====================

  /// 上传申请材料文件（基于文件路径）
  ///
  /// POST /content/upload
  /// 复用内容模块的文件上传接口
  Future<String> uploadMaterialFile({
    required String filePath,
    required String fileName,
  }) async {
    // 使用 Dio 的 FormData 和 MultipartFile
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'type': 'copyright_material',
    });

    final data = await _client.upload<Map<String, dynamic>>(
      '/content/upload',
      formData: formData,
      parser: (raw) => raw as Map<String, dynamic>,
    );

    final url = data?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('文件上传失败');
    }

    return url;
  }

  /// 上传申请材料文件（基于字节数组）
  ///
  /// POST /content/upload
  /// 复用内容模块的文件上传接口
  Future<String> uploadMaterialFileBytes({
    required List<int> bytes,
    required String fileName,
  }) async {
    // 使用 Dio 的 FormData 和 MultipartFile
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      'type': 'copyright_material',
    });

    final data = await _client.upload<Map<String, dynamic>>(
      '/content/upload',
      formData: formData,
      parser: (raw) => raw as Map<String, dynamic>,
    );

    final url = data?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('文件上传失败');
    }

    return url;
  }

  // ==================== 版权交割 ====================

  /// 获取交割列表
  Future<DeliveryListResponse> getDeliveryList({
    String? role,
    String? status,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    final params = <String, dynamic>{
      'pageNum': pageNum,
      'pageSize': pageSize,
    };
    if (role != null && role.isNotEmpty) {
      params['role'] = role;
    }
    if (status != null && status.isNotEmpty) {
      params['status'] = status;
    }

    final data = await _client.get(
      '/content/copyright/delivery/list',
      query: params,
    );

    return DeliveryListResponse.fromJson(data as Map<String, dynamic>);
  }

  /// 获取交割详情
  Future<CopyrightDelivery> getDeliveryDetail(int deliveryId) async {
    final data = await _client.get(
      '/content/copyright/delivery/$deliveryId',
    );

    return CopyrightDelivery.fromJson(data as Map<String, dynamic>);
  }

  /// 上传交割内容
  Future<void> uploadDelivery(int deliveryId) async {
    await _client.post(
      '/content/copyright/delivery/$deliveryId/upload',
    );
  }

  /// 确认收货
  Future<void> confirmDelivery(int deliveryId) async {
    await _client.post(
      '/content/copyright/delivery/$deliveryId/confirm',
    );
  }
}
