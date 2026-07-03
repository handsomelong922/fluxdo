import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/navigation/nav_action_bus.dart';

void main() {
  test('collapseNavScrollProgress quantizes scroll state', () {
    expect(collapseNavScrollProgress(-20), 0.0);
    expect(collapseNavScrollProgress(0), 0.0);
    expect(collapseNavScrollProgress(16), 1.0);
    expect(collapseNavScrollProgress(navScrollIconThreshold - 1), 1.0);
    expect(
      collapseNavScrollProgress(navScrollIconThreshold),
      navScrollIconThreshold,
    );
    expect(
      collapseNavScrollProgress(navScrollIconThreshold + 200),
      navScrollIconThreshold,
    );
  });
}
