import 'package:flutter/material.dart';
import 'dart:collection';
import '../../services/emoji_handler.dart';
import '../../services/discourse_cache_manager.dart';
import '../../utils/emoji_shortcodes.dart';

/// 轻量级 Emoji 文本组件
/// 
/// 将文本中的 :emoji_name: 替换为图片显示，
/// 使用 Text.rich + WidgetSpan 实现，无需完整 HTML 渲染库。
class EmojiText extends StatelessWidget {
  static const int _maxTokenCacheEntries = 512;
  static final LinkedHashMap<String, List<_EmojiSpanToken>> _tokenCache =
      LinkedHashMap<String, List<_EmojiSpanToken>>();

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  const EmojiText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
  });

  // 匹配 :emoji_name: 模式
  static final RegExp emojiRegex = emojiShortcodeRegex;

  @override
  Widget build(BuildContext context) {
    final spans = _buildSpans(context);
    
    // 如果没有 emoji，直接返回普通 Text
    if (spans.length == 1 && spans.first is TextSpan) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        softWrap: softWrap,
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }

  List<InlineSpan> _buildSpans(BuildContext context) {
    return buildEmojiSpans(context, text, style);
  }

  /// 静态方法：构建包含 emoji 的 spans 列表
  /// 可被其他组件复用
  static List<InlineSpan> buildEmojiSpans(
    BuildContext context,
    String text,
    TextStyle? style, {
    bool preserveSourceLength = false,
  }) {
    if (!text.contains(':')) {
      return [TextSpan(text: text)];
    }

    final tokens = _tokenCache.remove(text) ?? _parseTokens(text);
    _tokenCache[text] = tokens;
    while (_tokenCache.length > _maxTokenCacheEntries) {
      _tokenCache.remove(_tokenCache.keys.first);
    }

    if (tokens.length == 1 && tokens.first.text != null) {
      return [TextSpan(text: text)];
    }

    final spans = <InlineSpan>[];
    for (final token in tokens) {
      if (token.text case final value?) {
        if (value.isNotEmpty) {
          spans.add(TextSpan(text: value));
        }
        continue;
      }

      spans.add(_buildEmojiWidgetSpan(context, token.emojiName!, style));
      if (preserveSourceLength && token.sourceLength > 1) {
        spans.add(
          TextSpan(
            text: '\u2060' * (token.sourceLength - 1),
            style: style?.copyWith(color: Colors.transparent),
          ),
        );
      }
    }

    return spans;
  }

  static List<_EmojiSpanToken> _parseTokens(String text) {
    final matches = emojiRegex.allMatches(text);
    if (matches.isEmpty) {
      return [const _EmojiSpanToken.text('')];
    }

    final tokens = <_EmojiSpanToken>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        tokens.add(_EmojiSpanToken.text(text.substring(lastEnd, match.start)));
      }
      final emojiName = match.group(1);
      if (emojiName != null && emojiName.isNotEmpty) {
        tokens.add(
          _EmojiSpanToken.emoji(
            emojiName,
            sourceLength: match.end - match.start,
          ),
        );
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      tokens.add(_EmojiSpanToken.text(text.substring(lastEnd)));
    }
    return tokens;
  }

  static WidgetSpan _buildEmojiWidgetSpan(BuildContext context, String emojiName, TextStyle? style) {
    // 获取当前文字大小，emoji 稍大于文字
    final fontSize = style?.fontSize ?? 
        DefaultTextStyle.of(context).style.fontSize ?? 
        14.0;
    final emojiSize = fontSize * 1.2;

    // 获取 emoji URL
    final emojiUrl = EmojiHandler().getEmojiUrl(emojiName);

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Image(
          image: emojiImageProvider(emojiUrl),
          width: emojiSize,
          height: emojiSize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // 加载失败时显示原文本
            return Text(
              ':$emojiName:',
              style: style?.copyWith(fontSize: fontSize) ?? 
                  TextStyle(fontSize: fontSize),
            );
          },
        ),
      ),
    );
  }
}

class _EmojiSpanToken {
  const _EmojiSpanToken.text(this.text)
    : emojiName = null,
      sourceLength = 0;

  const _EmojiSpanToken.emoji(this.emojiName, {required this.sourceLength})
    : text = null;

  final String? text;
  final String? emojiName;
  final int sourceLength;
}

/// 可选择的 Emoji 文本组件
/// 
/// 用于需要支持文本选择的场景（如话题详情页标题）
class SelectableEmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final GlobalKey? textKey;

  const SelectableEmojiText(
    this.text, {
    super.key,
    this.style,
    this.textKey,
  });

  @override
  Widget build(BuildContext context) {
    final spans = EmojiText.buildEmojiSpans(context, text, style);
    
    // 如果没有 emoji，直接返回普通 SelectableText
    if (spans.length == 1 && spans.first is TextSpan) {
      return SelectableText(
        text,
        key: textKey,
        style: style,
      );
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      key: textKey,
      style: style,
    );
  }
}
