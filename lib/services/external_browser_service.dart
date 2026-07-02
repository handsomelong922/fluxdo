import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExternalBrowserApp {
  final String packageName;
  final String label;

  const ExternalBrowserApp({required this.packageName, required this.label});

  factory ExternalBrowserApp.fromMap(Map<Object?, Object?> map) {
    final packageName = (map['packageName'] as String?)?.trim() ?? '';
    final label = (map['label'] as String?)?.trim() ?? '';
    return ExternalBrowserApp(
      packageName: packageName,
      label: label.isEmpty ? packageName : label,
    );
  }
}

class ExternalBrowserService {
  static const MethodChannel channel = MethodChannel(
    'com.github.lingyan000.fluxdo/browser',
  );

  @visibleForTesting
  static bool? debugIsAndroidOverride;

  static bool get _supportsManagedBrowserSelection =>
      debugIsAndroidOverride ?? Platform.isAndroid;

  static Future<List<ExternalBrowserApp>> listAvailableBrowsers() async {
    if (!_supportsManagedBrowserSelection) {
      return const <ExternalBrowserApp>[];
    }

    try {
      final result = await channel.invokeMethod<List<dynamic>>('listBrowsers');
      if (result == null) return const <ExternalBrowserApp>[];

      return result
          .whereType<Map>()
          .map((item) => ExternalBrowserApp.fromMap(item))
          .where((item) => item.packageName.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[ExternalBrowserService] listBrowsers failed: $e');
      return const <ExternalBrowserApp>[];
    }
  }

  static Future<bool> openUrl(String url, {String? packageName}) async {
    if (!_supportsManagedBrowserSelection) {
      return false;
    }

    try {
      final result = await channel.invokeMethod<bool>('openInBrowser', {
        'url': url,
        if (packageName != null && packageName.isNotEmpty)
          'packageName': packageName,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[ExternalBrowserService] openInBrowser failed: $e');
      return false;
    }
  }
}
