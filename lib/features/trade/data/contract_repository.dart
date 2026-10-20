import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'trade_models.dart';

/// 合同域数据层。
///
/// 提供合同查询与签署接口，对接后端 `/api/v1/trade/contracts/*`。
class ContractRepository {
  ContractRepository(this._api);

  final ApiClient _api;

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
  /// 至少传一项。
  Future<ContractDetail> signContract(
    int contractId, {
    Uint8List? signatureImage,
    Uint8List? sealImage,
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
    });

    final data = await _api.upload<Map<String, dynamic>>(
      ApiEndpoints.appContractSign(contractId),
      formData: formData,
      parser: _mapParser,
    );
    if (data == null) throw ApiException('签署合同失败');
    return ContractDetail.fromJson(data);
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw == null) return <String, dynamic>{};
    if (raw is Map<String, dynamic>) return raw;
    return <String, dynamic>{};
  }
}
