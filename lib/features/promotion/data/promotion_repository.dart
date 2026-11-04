import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../user_center/data/paged_data.dart';
import 'promotion_models.dart';

/// 作品推广数据层：接口参数组装与信封解析，鉴权由 [ApiClient] 统一处理。
class PromotionRepository {
  PromotionRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  /// 后端 Jackson 统一按 `yyyy-MM-dd HH:mm:ss`（GMT+8）解析日期字符串。
  static String _formatDateTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  /// 指定资源位的位次列表（hot / search / banner）。
  Future<PromotionSlotPage> listSlots(String slotType) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentPromotionSlots,
      query: {'slotType': slotType},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('加载推广位次失败');
    return PromotionSlotPage.fromJson(data, slotType);
  }

  /// 上传轮播素材（复用内容模块 `/content/upload`，type=cover 仅接受图片）。
  Future<String> uploadBannerMaterial({
    required List<int> bytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      'type': 'cover',
    });
    final data = await _api.upload<Map<String, dynamic>>(
      '/content/upload',
      formData: formData,
      parser: _mapParser,
    );
    final url = data?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw ApiException('轮播素材上传失败');
    }
    return url;
  }

  /// 提交推广申请（days 仅支持 7 / 15 / 30）。
  ///
  /// [startTime] 为期望开始日期；后端按 `yyyy-MM-dd HH:mm:ss`（GMT+8）解析，
  /// 早于当前时刻会被服务端收敛为「立即生效」。
  Future<PromotionApplication> apply({
    required int workId,
    required String slotType,
    required int slotNo,
    required int days,
    DateTime? startTime,
    String? materialUrl,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentPromotionApplications,
      data: {
        'workId': workId,
        'slotType': slotType,
        'slotNo': slotNo,
        'days': days,
        if (startTime != null) 'startTime': _formatDateTime(startTime),
        if (materialUrl != null && materialUrl.isNotEmpty)
          'materialUrl': materialUrl,
      },
      parser: _mapParser,
    );
    if (data == null) throw ApiException('提交推广申请失败');
    final rawApplication = data['application'];
    final application = rawApplication is Map
        ? PromotionApplication.fromJson(
            Map<String, dynamic>.from(rawApplication))
        : null;
    final applyId =
        (data['applyId'] as num?)?.toInt() ?? application?.applyId ?? 0;
    if (applyId <= 0) throw ApiException('提交推广申请失败');
    return application ??
        PromotionApplication(
          applyId: applyId,
          workId: workId,
          slotType: slotType,
          slotNo: slotNo,
          days: days,
          status: 'pending',
          payStatus: 'unpaid',
          statusLabel: '待审核',
        );
  }

  /// 我的推广列表（viewStatus 为空时返回全部）。
  Future<PagedData<PromotionApplication>> myApplications(
      {String? viewStatus}) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentPromotionMyApplications,
      query: viewStatus == null || viewStatus.isEmpty
          ? null
          : {'viewStatus': viewStatus},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('加载推广记录失败');
    return PagedData.parse<PromotionApplication>(
        data, PromotionApplication.fromJson);
  }

  /// 推广申请详情。
  Future<PromotionApplication> detail(int applyId) async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.contentPromotionApplication(applyId),
      parser: _mapParser,
    );
    if (data == null || data.isEmpty) throw ApiException('推广详情加载失败');
    return PromotionApplication.fromJson(data);
  }

  /// 取消推广申请（仅待审核 / 待支付可取消）。
  Future<void> cancel(int applyId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.contentPromotionCancel(applyId),
      parser: _mapParser,
    );
  }

  /// 创建支付宝沙箱支付，返回收款二维码。
  Future<PromotionPaymentOrder> createPayment(int applyId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.tradePromotionPay(applyId),
      data: const <String, dynamic>{},
      parser: _mapParser,
    );
    if (data == null || (data['qrCode']?.toString().isEmpty ?? true)) {
      throw ApiException('创建支付失败');
    }
    return PromotionPaymentOrder.fromJson(data);
  }

  /// 查询支付结果（等待用户扫码期间轮询）。
  Future<PromotionPaymentConfirm> confirmPayment(int applyId) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.tradePromotionConfirm(applyId),
      data: const <String, dynamic>{},
      parser: _mapParser,
    );
    if (data == null) throw ApiException('查询支付结果失败');
    return PromotionPaymentConfirm.fromJson(data);
  }
}
