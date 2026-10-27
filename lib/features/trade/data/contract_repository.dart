import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'trade_models.dart';

/// 合同域数据层。
///
/// 提供合同查询与签署接口，对接后端 `/api/v1/trade/contracts/*`。
class ContractRepository {
  ContractRepository(this._api);

  final ApiClient _api;

  /// 我的合同列表（分页）。
  ///
  /// [role]：buyer=我作为买方 / seller=我作为卖方 / null=两者并集；
  /// [status]：pending / partial_signed / completed / null=全部。
  /// 列表项不含正文大字段与分页图，仅作摘要展示；进入详情再走 [getContractByOrder]。
  Future<PagedData<ContractDetail>> listContracts({
    String? role,
    String? status,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appContractList,
      query: <String, dynamic>{
        if (role != null && role.isNotEmpty) 'role': role,
        if (status != null && status.isNotEmpty) 'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
      parser: _mapParser,
    );
    if (data == null) throw ApiException('获取合同列表失败');
    return PagedData.parse<ContractDetail>(data, ContractDetail.fromJson);
  }

  /// 按订单 ID 取合同详情。
  Future<ContractDetail?> getContractByOrder(int orderId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.appContractByOrder(orderId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) return null;
    return ContractDetail.fromJson(data);
  }

  /// 签署合同。
  ///
  /// [signatureImage] 手写签名图片 PNG 字节（可选）。
  /// [sealImage] 印章图片 PNG 字节（可选）。
  /// [placements] 上传件签章定位 JSON 数组字符串（source_type=uploaded 时必传）。
  /// 至少传一项签名或印章。
  Future<ContractDetail> signContract(
    int contractId, {
    Uint8List? signatureImage,
    Uint8List? sealImage,
    String? placements,
  }) async {
    final formData = FormData.fromMap({
      if (signatureImage != null)
        'signatureImage': MultipartFile.fromBytes(
          signatureImage,
          filename: 'signature_${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      if (sealImage != null)
        'sealImage': MultipartFile.fromBytes(
          sealImage,
          filename: 'seal_${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      if (placements != null && placements.isNotEmpty) 'placements': placements,
    });

    final data = await _api.upload<Map<String, dynamic>>(
      ApiEndpoints.appContractSign(contractId),
      formData: formData,
      parser: _mapParser,
    );
    if (data == null) throw ApiException('签署合同失败');
    return ContractDetail.fromJson(data);
  }

  /// 平台合同模板目录（[{templateId, name, defaultClausesText}]）。
  ///
  /// [contractId] 传入时后端按该合同的作品/许可/金额生成贴合默认条款。
  Future<List<ContractTemplate>> listContractTemplates({int? contractId}) async {
    final data = await _api.get<List<dynamic>>(
      ApiEndpoints.appContractTemplates,
      query: contractId != null ? {'contractId': contractId} : null,
      parser: (raw) => raw is List ? raw : <dynamic>[],
    );
    return (data ?? <dynamic>[])
        .whereType<Map>()
        .map((e) => ContractTemplate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 编辑合同正文条款（未进入签署时可改，任一方已签即锁定）。
  ///
  /// 锁定/非法参数由后端返回 code=500 + message，抛 [ApiException] 供上层弹提示。
  Future<ContractDetail> updateContractContent(
    int contractId, {
    required String templateId,
    required String clausesText,
  }) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.appContractContent(contractId),
      data: {'templateId': templateId, 'clausesText': clausesText},
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('保存合同内容失败');
    return ContractDetail.fromJson(data);
  }

  /// 上传 PDF 替换平台模板（multipart：file）。
  ///
  /// 未签署前买卖双方均可上传覆盖（以最后一次为准）；上传件不可在线编辑。
  Future<ContractDetail> uploadContractSourcePdf(
    int contractId,
    Uint8List pdfBytes, {
    String fileName = 'contract.pdf',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(pdfBytes, filename: fileName),
    });
    final data = await _api.upload<Map<String, dynamic>>(
      ApiEndpoints.appContractSourcePdf(contractId),
      formData: formData,
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('上传合同失败');
    return ContractDetail.fromJson(data);
  }

  /// 从上传件切回平台模板（body：{ templateId }）；仅在未签署时可用。
  Future<ContractDetail> switchContractToTemplate(
    int contractId, {
    required String templateId,
  }) async {
    final data = await _api.put<Map<String, dynamic>>(
      ApiEndpoints.appContractSourcePdfOff(contractId),
      data: {'templateId': templateId},
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('切回模板失败');
    return ContractDetail.fromJson(data);
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw == null) return <String, dynamic>{};
    if (raw is Map<String, dynamic>) return raw;
    return <String, dynamic>{};
  }
}
