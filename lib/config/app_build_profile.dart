/// 当前安装包的网络功能形态。
///
/// 默认 `full` 保持原有能力；使用
/// `--dart-define=appNetworkProfile=direct` 构建个人直连版。
enum AppNetworkProfile {
  full,
  direct;

  static const AppNetworkProfile current = _rawProfile == 'direct'
      ? AppNetworkProfile.direct
      : AppNetworkProfile.full;

  static const String _rawProfile = String.fromEnvironment(
    'appNetworkProfile',
    defaultValue: 'full',
  );

  static bool get isDirect => current == AppNetworkProfile.direct;
  static bool get supportsAdvancedNetwork => current == AppNetworkProfile.full;
  static bool get supportsRhttp => supportsAdvancedNetwork;
  static bool get supportsDohProxy => supportsAdvancedNetwork;
}
