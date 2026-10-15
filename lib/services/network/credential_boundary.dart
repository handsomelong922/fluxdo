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
