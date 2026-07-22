import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/s.dart';
import '../../../models/topic.dart';
import '../../../services/toast_service.dart';
import '../../../utils/code_selection_context.dart';
import '../../../utils/html_text_mapper.dart';
import '../../../utils/html_to_markdown.dart';
import '../../../utils/quote_builder.dart';

typedef QuoteSelectionCallback = void Function(String selectedText, Post post);
typedef SearchSelectionCallback = void Function(String selectedText);

class QuoteSelectionHelper {
  const QuoteSelectionHelper._();

  static final ValueNotifier<bool> selectionActiveListenable =
      ValueNotifier<bool>(false);
  static final Set<Object> _activeSelectionSources = Set<Object>.identity();

  static bool get isSelectionActive => selectionActiveListenable.value;

  static void updateSelectionActive(Object source, String? plainText) {
    if (plainText != null && plainText.trim().isNotEmpty) {
      _activeSelectionSources.add(source);
    } else {
      _activeSelectionSources.remove(source);
    }
    _syncSelectionActivity();
  }

  static void clearSelectionSource(Object source) {
    _activeSelectionSources.remove(source);
    _syncSelectionActivity();
  }

  static void resetSelectionActivity() {
    _activeSelectionSources.clear();
    _syncSelectionActivity();
  }

  static void _syncSelectionActivity() {
    selectionActiveListenable.value = _activeSelectionSources.isNotEmpty;
  }

  static String buildQuoteSelectionText(
    String plainText, {
    CodeSelectionContext? codeContext,
  }) {
    final normalizedText = plainText.trim();
    if (normalizedText.isEmpty) return '';

    if (codeContext != null) {
      return CodeSelectionContextTracker.instance.encodePayload(
        normalizedText,
        context: codeContext,
      );
    }

    return normalizedText;
  }

  static void copyQuoteToClipboard({
    required String selectedText,
    required Post post,
    required int topicId,
    CodeSelectionContext? fallbackCodeContext,
  }) {
    final codePayload = CodeSelectionContextTracker.instance.decodePayload(
      selectedText,
    );
    final plainSelectedText = codePayload?.text ?? selectedText;
    final codeContext = codePayload?.context ?? fallbackCodeContext;
    String markdown;

    final htmlFragment = HtmlTextMapper.extractHtml(
      post.cooked,
      plainSelectedText,
    );
    if (htmlFragment != null) {
      markdown = HtmlToMarkdown.convert(htmlFragment);
      if (markdown.trim().isEmpty) {
        markdown = codeContext != null
            ? CodeSelectionContextTracker.instance.toMarkdown(
                plainSelectedText,
                context: codeContext,
              )
            : plainSelectedText;
      }
    } else if (codeContext != null) {
      markdown = CodeSelectionContextTracker.instance.toMarkdown(
        plainSelectedText,
        context: codeContext,
      );
    } else {
      markdown = plainSelectedText;
    }

    final quote = QuoteBuilder.build(
      markdown: markdown,
      username: post.username,
      postNumber: post.postNumber,
      topicId: topicId,
    );

    Clipboard.setData(ClipboardData(text: quote));
    ToastService.showSuccess(S.current.common_quoteCopied);
  }

  static List<ContextMenuButtonItem> buildMenuItems({
    required List<ContextMenuButtonItem> baseItems,
    required String? plainText,
    required Post? post,
    required VoidCallback hideToolbar,
    required int topicId,
    QuoteSelectionCallback? onQuoteSelection,
    SearchSelectionCallback? onSearchSelection,
    CodeSelectionContext? codeContext,
  }) {
    final hasSelectedText = plainText != null && plainText.trim().isNotEmpty;
    if (!hasSelectedText) {
      return baseItems;
    }

    if (onSearchSelection == null &&
        (onQuoteSelection == null || post == null)) {
      return baseItems;
    }

    final items = List<ContextMenuButtonItem>.from(baseItems);
    if (onSearchSelection != null) {
      items.insert(
        0,
        ContextMenuButtonItem(
          label: S.current.common_search,
          onPressed: () {
            onSearchSelection(plainText.trim());
            hideToolbar();
          },
        ),
      );
    }

    if (onQuoteSelection == null || post == null) {
      return items;
    }

    if (plainText.trim().isEmpty) {
      return items;
    }

    final quoteInsertIndex = onSearchSelection == null ? 0 : 1;
    items.insert(
      quoteInsertIndex,
      ContextMenuButtonItem(
        label: S.current.common_quote,
        onPressed: () {
          final quoteText = buildQuoteSelectionText(
            plainText,
            codeContext: codeContext,
          );
          if (quoteText.isNotEmpty) {
            onQuoteSelection(quoteText, post);
          }
          hideToolbar();
        },
      ),
    );
    items.insert(
      quoteInsertIndex + 1,
      ContextMenuButtonItem(
        label: S.current.common_copyQuote,
        onPressed: () {
          copyQuoteToClipboard(
            selectedText: plainText,
            post: post,
            topicId: topicId,
            fallbackCodeContext: codeContext,
          );
          hideToolbar();
        },
      ),
    );

    return items;
  }
}
