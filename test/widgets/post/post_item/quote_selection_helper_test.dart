import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/post/post_item/quote_selection_helper.dart';

void main() {
  setUp(QuoteSelectionHelper.resetSelectionActivity);
  tearDown(QuoteSelectionHelper.resetSelectionActivity);

  test('一个来源的空选择不会清除另一个来源的有效选择', () {
    final sourceA = Object();
    final sourceB = Object();

    QuoteSelectionHelper.updateSelectionActive(sourceA, 'selected');
    QuoteSelectionHelper.updateSelectionActive(sourceB, null);

    expect(QuoteSelectionHelper.isSelectionActive, isTrue);
  });

  test('最后一个有效选择释放后 blocker 才关闭', () {
    final sourceA = Object();
    final sourceB = Object();

    QuoteSelectionHelper.updateSelectionActive(sourceA, 'first');
    QuoteSelectionHelper.updateSelectionActive(sourceB, 'second');
    QuoteSelectionHelper.updateSelectionActive(sourceA, null);
    expect(QuoteSelectionHelper.isSelectionActive, isTrue);

    QuoteSelectionHelper.clearSelectionSource(sourceB);
    expect(QuoteSelectionHelper.isSelectionActive, isFalse);
  });
}
