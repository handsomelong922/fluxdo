import 'dart:math';

/// linux.do 系 OAuth 链路共用的拟人化节奏工具。
///
/// 这里只负责在相邻请求间加入随机延迟，避免固定间隔被识别为脚本。
/// 不构造 Sec-Fetch / Referer 等导航伪装头；上游实测这些头会增加
/// callback CSRF 失败风险。
class OAuthFlowHelper {
  OAuthFlowHelper._();

  static final Random _random = Random();

  static Future<void> humanGap({
    required int minMs,
    required int maxMs,
  }) async {
    assert(minMs > 0 && maxMs >= minMs);
    final delay = minMs + _random.nextInt(maxMs - minMs + 1);
    await Future<void>.delayed(Duration(milliseconds: delay));
  }
}
