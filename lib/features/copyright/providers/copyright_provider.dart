/// 版权管理状态管理（App 端）。
library;

import 'package:flutter/foundation.dart';
import '../data/copyright_api_service.dart';
import '../data/copyright_models.dart';

class CopyrightProvider extends ChangeNotifier {
  final CopyrightApiService _apiService;

  CopyrightProvider(this._apiService);

  // 暴露 apiService 以便页面直接调用（如文件上传）
  CopyrightApiService get apiService => _apiService;

  // ==================== 版权申请列表 ====================

  bool _applicationLoading = false;
  bool get applicationLoading => _applicationLoading;

  List<CopyrightApplication> _applications = [];
  List<CopyrightApplication> get applications => _applications;

  int _applicationTotal = 0;
  int get applicationTotal => _applicationTotal;

  String? _applicationError;
  String? get applicationError => _applicationError;

  /// 加载版权申请列表
  Future<void> loadApplications({
    int pageNum = 1,
    int pageSize = 10,
    String? status,
    String? workName,
  }) async {
    _applicationLoading = true;
    _applicationError = null;
    notifyListeners();

    try {
      final result = await _apiService.getMyApplications(
        pageNum: pageNum,
        pageSize: pageSize,
        status: status,
        workName: workName,
      );

      _applications = result['rows'] as List<CopyrightApplication>;
      _applicationTotal = result['total'] as int;
      _applicationError = null;
    } catch (e) {
      _applicationError = e.toString();
      _applications = [];
      _applicationTotal = 0;
    } finally {
      _applicationLoading = false;
      notifyListeners();
    }
  }

  /// 刷新申请列表
  Future<void> refreshApplications() async {
    await loadApplications();
  }

  // ==================== 版权申请详情 ====================

  bool _applicationDetailLoading = false;
  bool get applicationDetailLoading => _applicationDetailLoading;

  CopyrightApplication? _currentApplication;
  CopyrightApplication? get currentApplication => _currentApplication;

  String? _applicationDetailError;
  String? get applicationDetailError => _applicationDetailError;

  /// 加载版权申请详情
  Future<void> loadApplicationDetail(int applyId) async {
    _applicationDetailLoading = true;
    _applicationDetailError = null;
    notifyListeners();

    try {
      _currentApplication = await _apiService.getApplicationDetail(applyId);
      _applicationDetailError = null;
    } catch (e) {
      _applicationDetailError = e.toString();
      _currentApplication = null;
    } finally {
      _applicationDetailLoading = false;
      notifyListeners();
    }
  }

  // ==================== 提交版权申请 ====================

  bool _submitting = false;
  bool get submitting => _submitting;

  /// 提交版权申请
  Future<bool> submitApplication(CopyrightApplyDTO dto) async {
    _submitting = true;
    notifyListeners();

    try {
      await _apiService.submitApplication(dto);
      _submitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _submitting = false;
      notifyListeners();
      rethrow;
    }
  }

  /// 重新提交版权申请
  Future<bool> resubmitApplication(CopyrightResubmitDTO dto) async {
    _submitting = true;
    notifyListeners();

    try {
      await _apiService.resubmitApplication(dto);
      _submitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _submitting = false;
      notifyListeners();
      rethrow;
    }
  }

  /// 删除版权申请（仅限pending状态）
  Future<bool> deleteApplication(int applyId) async {
    try {
      await _apiService.deleteApplication(applyId);
      // 删除成功后刷新列表
      await refreshApplications();
      return true;
    } catch (e) {
      rethrow;
    }
  }

  /// 更新版权申请（仅限pending状态）
  Future<bool> updateApplication(int applyId, CopyrightApplyDTO dto) async {
    _submitting = true;
    notifyListeners();

    try {
      await _apiService.updateApplication(applyId, dto);
      _submitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _submitting = false;
      notifyListeners();
      rethrow;
    }
  }

  // ==================== 版权证书列表 ====================

  bool _certificateLoading = false;
  bool get certificateLoading => _certificateLoading;

  List<CopyrightCert> _certificates = [];
  List<CopyrightCert> get certificates => _certificates;

  int _certificateTotal = 0;
  int get certificateTotal => _certificateTotal;

  String? _certificateError;
  String? get certificateError => _certificateError;

  /// 加载版权证书列表
  Future<void> loadCertificates({
    int pageNum = 1,
    int pageSize = 10,
    String? workName,
  }) async {
    _certificateLoading = true;
    _certificateError = null;
    notifyListeners();

    try {
      final result = await _apiService.getMyCertificates(
        pageNum: pageNum,
        pageSize: pageSize,
        workName: workName,
      );

      _certificates = result['rows'] as List<CopyrightCert>;
      _certificateTotal = result['total'] as int;
      _certificateError = null;
    } catch (e) {
      _certificateError = e.toString();
      _certificates = [];
      _certificateTotal = 0;
    } finally {
      _certificateLoading = false;
      notifyListeners();
    }
  }

  /// 刷新证书列表
  Future<void> refreshCertificates() async {
    await loadCertificates();
  }

  // ==================== 版权证书详情 ====================

  bool _certificateDetailLoading = false;
  bool get certificateDetailLoading => _certificateDetailLoading;

  CopyrightCert? _currentCertificate;
  CopyrightCert? get currentCertificate => _currentCertificate;

  String? _certificateDetailError;
  String? get certificateDetailError => _certificateDetailError;

  /// 加载版权证书详情
  Future<void> loadCertificateDetail(int certId) async {
    _certificateDetailLoading = true;
    _certificateDetailError = null;
    notifyListeners();

    try {
      _currentCertificate = await _apiService.getCertificateDetail(certId);
      _certificateDetailError = null;
    } catch (e) {
      _certificateDetailError = e.toString();
      _currentCertificate = null;
    } finally {
      _certificateDetailLoading = false;
      notifyListeners();
    }
  }

  /// 下载证书 PDF
  Future<String> downloadCertificatePdf(int certId) async {
    return await _apiService.downloadCertificatePdf(certId);
  }

  // ==================== 版权中心配置 ====================

  List<CopyrightCenter> _centers = [];
  List<CopyrightCenter> get centers => _centers;

  bool _centersLoading = false;
  bool get centersLoading => _centersLoading;

  /// 加载可用版权中心
  Future<void> loadActiveCenters() async {
    _centersLoading = true;
    notifyListeners();

    try {
      _centers = await _apiService.getActiveCenters();
    } catch (e) {
      _centers = [];
    } finally {
      _centersLoading = false;
      notifyListeners();
    }
  }

  // ==================== 我的作品列表 ====================

  List<MyWorkBrief> _myWorks = [];
  List<MyWorkBrief> get myWorks => _myWorks;

  bool _worksLoading = false;
  bool get worksLoading => _worksLoading;

  String? _worksError;
  String? get worksError => _worksError;

  /// 加载我的作品列表
  Future<void> loadMyWorks() async {
    _worksLoading = true;
    _worksError = null;
    notifyListeners();

    try {
      _myWorks = await _apiService.getMyWorks();
      _worksError = null;
    } catch (e) {
      _myWorks = [];
      _worksError = e.toString();
    } finally {
      _worksLoading = false;
      notifyListeners();
    }
  }

  /// 重置状态
  void reset() {
    _applications = [];
    _applicationTotal = 0;
    _applicationError = null;
    _currentApplication = null;
    _certificates = [];
    _certificateTotal = 0;
    _certificateError = null;
    _currentCertificate = null;
    _centers = [];
    _myWorks = [];
    _worksError = null;
    notifyListeners();
  }

  // ==================== 版权交割 ====================

  bool _deliveryLoading = false;
  bool get deliveryLoading => _deliveryLoading;

  List<CopyrightDelivery> _deliveries = [];
  List<CopyrightDelivery> get deliveries => _deliveries;

  int _deliveryTotal = 0;
  int get deliveryTotal => _deliveryTotal;

  String? _deliveryError;
  String? get deliveryError => _deliveryError;

  CopyrightDelivery? _currentDelivery;
  CopyrightDelivery? get currentDelivery => _currentDelivery;

  /// 加载交割列表
  Future<void> loadDeliveries({
    String? role,
    String? status,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    _deliveryLoading = true;
    _deliveryError = null;
    notifyListeners();

    try {
      final response = await _apiService.getDeliveryList(
        role: role,
        status: status,
        pageNum: pageNum,
        pageSize: pageSize,
      );
      _deliveries = response.list;
      _deliveryTotal = response.total;
      _deliveryError = null;
    } catch (e) {
      _deliveryError = e.toString();
      _deliveries = [];
      _deliveryTotal = 0;
    } finally {
      _deliveryLoading = false;
      notifyListeners();
    }
  }

  /// 加载交割详情
  Future<bool> loadDeliveryDetail(int deliveryId) async {
    _deliveryLoading = true;
    notifyListeners();

    try {
      _currentDelivery = await _apiService.getDeliveryDetail(deliveryId);
      _deliveryLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _deliveryError = e.toString();
      _deliveryLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 上传交割内容（须含证书文件）
  Future<bool> uploadDelivery(
    int deliveryId, {
    required List<Map<String, dynamic>> files,
    String? remark,
  }) async {
    _currentDelivery = await _apiService.uploadDelivery(
      deliveryId,
      files: files,
      remark: remark,
    );
    notifyListeners();
    return true;
  }

  /// 确认收货
  Future<bool> confirmDelivery(int deliveryId) async {
    _currentDelivery = await _apiService.confirmDelivery(deliveryId);
    notifyListeners();
    return true;
  }

  /// 按订单加载交割单
  Future<CopyrightDelivery?> loadDeliveryByOrder(int orderId) async {
    try {
      _currentDelivery = await _apiService.getDeliveryByOrder(orderId);
      notifyListeners();
      return _currentDelivery;
    } catch (e) {
      _deliveryError = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// 刷新交割列表
  Future<void> refreshDeliveries() async {
    await loadDeliveries();
  }
}
