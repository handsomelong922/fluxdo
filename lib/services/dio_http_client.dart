import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import '../constants.dart';
import 'network/discourse_dio.dart';

/// 包装 Dio 的 http.BaseClient 实现，供 flutter_cache_manager 下载图片/文件。
///
/// 主站图片可能需要 session cookie；第三方 CDN 不需要 cookie，单独使用
/// 轻量 Dio，避免大量 sticker/emoji 下载反复读写 cookie jar。
class DioHttpClient extends http.BaseClient {
  static DioHttpClient? _instance;

  final dio.Dio _mainDomainDio;
  final dio.Dio _cdnDio;

  factory DioHttpClient() {
    _instance ??= DioHttpClient._internal();
    return _instance!;
  }

  DioHttpClient._internal()
    : _mainDomainDio = DiscourseDio.create(
        defaultHeaders: _imageHeaders,
        maxConcurrent: null,
        enableCookies: true,
        enableCfChallenge: false,
        enableRetry: false,
        enableNetworkLog: false,
      ),
      _cdnDio = DiscourseDio.create(
        defaultHeaders: _imageHeaders,
        maxConcurrent: null,
        enableCookies: false,
        enableCfChallenge: false,
        enableRetry: false,
        enableNetworkLog: false,
      );

  static const Map<String, String> _imageHeaders = {
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  static final String _mainHost = Uri.parse(AppConstants.baseUrl).host;

  bool _isMainDomain(Uri url) {
    final host = url.host;
    if (host.isEmpty) return false;
    return host == _mainHost || host.endsWith('.$_mainHost');
  }

  dio.Dio _selectDio(Uri url) {
    return _isMainDomain(url) ? _mainDomainDio : _cdnDio;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      // 转换 headers
      final headers = <String, dynamic>{};
      request.headers.forEach((key, value) {
        headers[key] = value;
      });

      // 获取请求体
      Uint8List? bodyBytes;
      if (request is http.Request && request.bodyBytes.isNotEmpty) {
        bodyBytes = request.bodyBytes;
      } else if (request is http.MultipartRequest) {
        // MultipartRequest 需要特殊处理
        final stream = request.finalize();
        final bytes = await stream.toBytes();
        bodyBytes = Uint8List.fromList(bytes);
      }

      final response = await _selectDio(request.url).request<dio.ResponseBody>(
        request.url.toString(),
        options: dio.Options(
          method: request.method,
          headers: headers,
          responseType: dio.ResponseType.stream,
          // 接受所有状态码，让调用方处理
          validateStatus: (status) => true,
        ),
        data: bodyBytes != null ? Stream.fromIterable([bodyBytes]) : null,
      );

      // 转换响应 headers
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      // 获取 Content-Length
      final contentLengthStr = responseHeaders['content-length'];
      final contentLength = contentLengthStr != null
          ? int.tryParse(contentLengthStr)
          : null;

      // 获取流式响应体
      final responseBody = response.data;
      final Stream<List<int>> responseStream;

      if (responseBody != null) {
        // 直接使用 Dio 的流式响应
        responseStream = responseBody.stream;
      } else {
        responseStream = Stream.value(<int>[]);
      }

      return http.StreamedResponse(
        responseStream,
        response.statusCode ?? 200,
        headers: responseHeaders,
        contentLength: contentLength,
        request: request,
        reasonPhrase: response.statusMessage,
      );
    } on dio.DioException catch (e) {
      // 将 DioException 转换为 http 包可以理解的异常
      if (e.type == dio.DioExceptionType.connectionTimeout ||
          e.type == dio.DioExceptionType.receiveTimeout) {
        throw http.ClientException(
          'Request timeout: ${e.message}',
          request.url,
        );
      }
      throw http.ClientException('Dio error: ${e.message}', request.url);
    }
  }

  @override
  void close() {
    // 不关闭共享的 Dio 实例
  }
}
