import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 证书 PDF 落盘助手。
///
/// 与创作者端 [CertPanel] 一致：
/// - App/User 下载接口只返回 `certUrl`，开发期常为 `mock-cert.example.com`，不可直链下载；
/// - 能拉到真实 PDF 就用；否则回退本地 Mock PDF（对齐 Admin 侧 `generateMockPdf`）。
///
/// Android 正式保存走原生 MediaStore「下载」目录，系统文件管理器可见；
/// `getDownloadsDirectory()` 只是应用私有 `Android/data/.../files/downloads`，用户看不到。
class CertificateDownloadHelper {
  CertificateDownloadHelper({
    Dio? dio,
    Future<Directory> Function()? documentsDirectory,
    Future<String?> Function(String fileName, Uint8List bytes)? publicDownloadsSaver,
  })  : _dio = dio ?? Dio(),
        _documentsDirectory = documentsDirectory,
        _publicDownloadsSaver =
            publicDownloadsSaver ?? _defaultPublicDownloadsSaver;

  /// 测试注入：优先于默认构造。
  @visibleForTesting
  static CertificateDownloadHelper? debugOverride;

  /// 测试注入：打开本地文件（默认走 url_launcher）。
  @visibleForTesting
  static Future<bool> Function(Uri uri)? debugOpenFile;

  static const MethodChannel _fileChannel =
      MethodChannel('smartscript/native_file');

  static CertificateDownloadHelper create() =>
      debugOverride ?? CertificateDownloadHelper();

  final Dio _dio;
  /// 非空时强制使用该目录（单测）。
  final Future<Directory> Function()? _documentsDirectory;
  final Future<String?> Function(String fileName, Uint8List bytes)
      _publicDownloadsSaver;

  /// 是否落到了用户可见的「下载」目录（而非应用私有目录）。
  bool savedToPublicDownloads = false;

  /// 保存结果路径（公共目录可能是 content:// Uri）。
  String? savedPath;

  Future<File> saveCertificatePdf({
    required String url,
    required String fileName,
    String? certNo,
    String? workName,
  }) async {
    final bytes = await resolvePdfBytes(
      url: url,
      certNo: certNo,
      workName: workName,
    );
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    // 单测强制目录：不走原生通道。
    final docsGetter = _documentsDirectory;
    if (docsGetter != null) {
      final dir = await docsGetter();
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      savedToPublicDownloads = false;
      savedPath = file.path;
      return file;
    }

    // Android：MediaStore 写入系统 Download，文件管理器「下载」可见。
    if (Platform.isAndroid) {
      try {
        final path = await _publicDownloadsSaver(safeName, bytes);
        if (path != null && path.isNotEmpty) {
          savedToPublicDownloads = true;
          savedPath = path;
          // content:// 无法直接当 File 打开；仍返回一个占位路径供调用方判断成功。
          if (path.startsWith('content:')) {
            final cache = await getTemporaryDirectory();
            final mirror = File('${cache.path}/$safeName');
            await mirror.writeAsBytes(bytes, flush: true);
            return mirror;
          }
          return File(path);
        }
      } catch (_) {
        // 回退到私有目录，至少保证下载不失败。
      }
    }

    final fallback = await _resolvePrivateDirectory();
    final file = File('${fallback.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    savedToPublicDownloads = false;
    savedPath = file.path;
    return file;
  }

  Future<Directory> _resolvePrivateDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  static Future<String?> _defaultPublicDownloadsSaver(
    String fileName,
    Uint8List bytes,
  ) async {
    final result = await _fileChannel.invokeMethod<String>(
      'saveToPublicDownloads',
      <String, dynamic>{
        'fileName': fileName,
        'bytes': bytes,
        'mimeType': 'application/pdf',
      },
    );
    return result;
  }

  /// 下载任意远端材料并落盘（购买获得版权材料用；失败直接抛错，不做 Mock 证书回退）。
  Future<File> saveRemoteFile({
    required String url,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final data = resp.data;
    if (resp.statusCode != 200 || data == null || data.isEmpty) {
      throw Exception('文件下载失败');
    }
    final bytes = Uint8List.fromList(data);
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    final docsGetter = _documentsDirectory;
    if (docsGetter != null) {
      final dir = await docsGetter();
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      savedToPublicDownloads = false;
      savedPath = file.path;
      return file;
    }

    if (Platform.isAndroid) {
      try {
        final path = await _fileChannel.invokeMethod<String>(
          'saveToPublicDownloads',
          <String, dynamic>{
            'fileName': safeName,
            'bytes': bytes,
            'mimeType': mimeType,
          },
        );
        if (path != null && path.isNotEmpty) {
          savedToPublicDownloads = true;
          savedPath = path;
          if (path.startsWith('content:')) {
            final cache = await getTemporaryDirectory();
            final mirror = File('${cache.path}/$safeName');
            await mirror.writeAsBytes(bytes, flush: true);
            return mirror;
          }
          return File(path);
        }
      } catch (_) {}
    }

    final fallback = await _resolvePrivateDirectory();
    final file = File('${fallback.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    savedToPublicDownloads = false;
    savedPath = file.path;
    return file;
  }

  Future<Uint8List> resolvePdfBytes({
    required String url,
    String? certNo,
    String? workName,
  }) async {
    if (!_isMockCertUrl(url)) {
      try {
        final resp = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        final data = resp.data;
        if (resp.statusCode == 200 &&
            data != null &&
            data.isNotEmpty &&
            _looksLikePdf(data)) {
          return Uint8List.fromList(data);
        }
      } catch (_) {
        // 远端不可达时回退 Mock，与创作者端 tryFetchCertBlob 一致。
      }
    }
    return buildMockCertPdf(certNo: certNo, workName: workName);
  }

  static bool _isMockCertUrl(String url) =>
      RegExp(r'^https?://mock', caseSensitive: false).hasMatch(url.trim());

  static bool _looksLikePdf(List<int> bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46; // F
  }

  /// 最小可读 PDF，便于模拟器/开发环境直接落盘打开。
  static Uint8List buildMockCertPdf({String? certNo, String? workName}) {
    final no = (certNo == null || certNo.isEmpty) ? 'UNKNOWN' : certNo;
    final work = (workName == null || workName.isEmpty) ? '-' : workName;
    final stream =
        'BT /F1 18 Tf 50 720 Td (Copyright Certificate) Tj ET '
        'BT /F1 12 Tf 50 680 Td (Cert No: $no) Tj ET '
        'BT /F1 12 Tf 50 650 Td (Work: $work) Tj ET ';
    final pdf = StringBuffer()
      ..writeln('%PDF-1.4')
      ..writeln('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj')
      ..writeln('2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj')
      ..writeln(
          '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources<< /Font<< /F1<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>endobj')
      ..writeln('4 0 obj<< /Length ${stream.length} >>stream')
      ..writeln(stream)
      ..writeln('endstream endobj')
      ..writeln('xref')
      ..writeln('0 5')
      ..writeln('0000000000 65535 f ')
      ..writeln('trailer<< /Size 5 /Root 1 0 R >>')
      ..writeln('startxref')
      ..writeln('0')
      ..writeln('%%EOF');
    return Uint8List.fromList(utf8.encode(pdf.toString()));
  }
}
