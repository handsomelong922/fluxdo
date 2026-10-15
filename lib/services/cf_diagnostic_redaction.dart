/// 日志专用 URL 摘要：只保留 HTTP(S) 来源和路径，不返回认证信息、查询或片段。
///
/// 不用于请求或导航。路径仍可能含业务标识或凭据；本函数不是任意文本的
/// 通用脱敏器，也不保证其他日志入口的安全性。无法识别的输入整段省略。
String cfDiagnosticUrl(String value) {
  if (value.contains(RegExp(r'[\x00-\x20\x7f]'))) {
    return '[URL omitted]';
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return '[URL omitted]';
  if (uri.hasScheme) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      return '[URL omitted]';
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
  if (!uri.hasAuthority && uri.path.startsWith('/')) {
    return Uri(path: uri.path).toString();
  }
  return '[URL omitted]';
}

/// 异常字符串可能含请求头、Cookie、正文或非 URL 形式的凭据。
/// 不尝试用关键词替换猜测内容，仅保留是否提供了异常这一事实。
String cfDiagnosticError(String? error) =>
    error == null ? 'not provided' : '[error detail omitted]';
