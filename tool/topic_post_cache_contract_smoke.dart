import 'dart:io';

void main() {
  final source = File('lib/pages/topic_detail_page/widgets/topic_post_list.dart')
      .readAsStringSync();
  final signature = source.split('final signature = (').last.split(');').first;
  for (final input in [
    'categoryId: detail.categoryId',
    'assignmentInfo: detail.indirectlyAssignedTo[post.id]',
    'canAssignPost: widget.canAssignPost',
  ]) {
    if (!signature.contains(input)) {
      throw StateError('短帖缓存遗漏输入: $input');
    }
  }
  print('PASS: 分类、指派信息和指派权限均参与短帖缓存签名（源码契约）');
}
