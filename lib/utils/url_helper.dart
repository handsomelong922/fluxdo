import '../constants.dart';
import '../services/preloaded_data_service.dart';

class UrlHelper {
  /// 修复相对路径 URL
  /// 支持协议相对路径（//example.com/...）和站内相对路径（/path/...）
  /// 如果已加载 CDN 配置，相对路径会优先使用 CDN 域名
  static String resolveUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('http')) {
      return url;
    }
    final base = PreloadedDataService().cdnUrl ?? AppConstants.baseUrl;
    if (url.startsWith('/')) {
      return '$base$url';
    }
    // 相对路径（如 letter_avatar_proxy/v4/...）
    return '$base/$url';
  }
}
