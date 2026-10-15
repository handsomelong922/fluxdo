/// 凭据仅能沿相同 HTTPS 源传递。路径、查询和片段不改变源，
/// 子域及不同端口则是独立源；带用户信息的 URL 保守视为不可信。
bool isSameHttpsOrigin(Uri source, Uri target) {
  return source.scheme == 'https' &&
      target.scheme == 'https' &&
      source.host.isNotEmpty &&
      source.userInfo.isEmpty &&
      target.userInfo.isEmpty &&
      source.host == target.host &&
      source.port == target.port;
}

/// 重定向每一跳重新挑选可转发的请求头，不修改原请求快照。
/// Cookie 始终交目标 URL 的 CookieJar 重取；其他认证只在同源 HTTPS
/// 间保留。直接请求第三方 API 的独立 Authorization 不经过此函数。
Map<String, dynamic> redirectRequestHeaders(
  Map<String, dynamic> headers, {
  required Uri source,
  required Uri target,
}) {
  final sameOrigin = isSameHttpsOrigin(source, target);
  return {
    for (final entry in headers.entries)
      if (entry.key.toLowerCase() != 'cookie' &&
          (sameOrigin ||
              !_originBoundHeaders.contains(entry.key.toLowerCase())))
        entry.key: entry.value,
  };
}

const _originBoundHeaders = {
  'authorization',
  'proxy-authorization',
  'x-csrf-token',
  'user-api-key',
  'api-key',
  'api-username',
  'user-api-client-id',
  'discourse-logged-in',
  'discourse-present',
};
