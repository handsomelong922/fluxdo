import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_post_list.dart';

void main() {
  test('topic post render identity ignores network post id handoff', () {
    final previewKey = topicPostRenderIdentityKey(
      topicId: 42,
      postNumber: 1,
      segmentType: 'post',
    );
    final loadedKey = topicPostRenderIdentityKey(
      topicId: 42,
      postNumber: 1,
      segmentType: 'post',
    );

    expect(loadedKey, previewKey);
  });

  test('topic post render identity separates chunks and topics', () {
    expect(
      topicPostRenderIdentityKey(
        topicId: 42,
        postNumber: 1,
        segmentType: 'long-chunk',
        chunkIndex: 2,
      ),
      isNot(
        topicPostRenderIdentityKey(
          topicId: 42,
          postNumber: 1,
          segmentType: 'long-chunk',
          chunkIndex: 3,
        ),
      ),
    );
    expect(
      topicPostRenderIdentityKey(
        topicId: 42,
        postNumber: 1,
        segmentType: 'post',
      ),
      isNot(
        topicPostRenderIdentityKey(
          topicId: 43,
          postNumber: 1,
          segmentType: 'post',
        ),
      ),
    );
  });
}
