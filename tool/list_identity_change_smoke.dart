import '../lib/utils/list_identity_change.dart';

class _Row {
  const _Row(this.id, this.height);
  final int id;
  final int height;
}

void runListIdentityChangeChecks() {
  final a = _Row(1, 100);
  final b = _Row(2, 120);
  final c = _Row(3, 90);
  final rows = [a, b];
  ListIdentityChange classify(List<_Row>? before, List<_Row> after) =>
      classifyListIdentityChange(before, after, identityOf: (row) => row.id);
  void check(bool value, String label) {
    if (!value) throw StateError(label);
  }

  check(classify(null, rows) == ListIdentityChange.initial, '首次构建');
  check(classify(rows, rows) == ListIdentityChange.unchanged, '同一列表');
  check(classify(rows, [a, b]) == ListIdentityChange.unchanged, '过滤复制不换行');
  check(classify(rows, [a, b, c]) == ListIdentityChange.tailAppend, '尾追加');
  check(
    classify(rows, [_Row(1, 150), b]) == ListIdentityChange.contentChanged,
    '行高度更新保留锚定',
  );
  check(classify(rows, [c, a, b]) == ListIdentityChange.structural, '头插入');
  check(classify(rows, [b]) == ListIdentityChange.structural, '隐藏行移除');
  check(classify(rows, [b, a]) == ListIdentityChange.structural, '换序');
  check(
    classify(rows, [_Row(1, 150), b, c]) == ListIdentityChange.structural,
    '改行并追加',
  );
  check(classify(rows, []) == ListIdentityChange.structural, '清空');
}

void main() {
  runListIdentityChangeChecks();
  print('PASS: 10 项可见行身份与锚定分类检查');
}
