part of 'discourse_service.dart';

mixin _RevisionsMixin on _DiscourseServiceBase {
  Future<PostRevision> getPostRevision(int postId, int revision) async {
    try {
      final response = await _dio.get(
        '/posts/$postId/revisions/$revision.json',
      );
      return PostRevision.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<PostRevision> getLatestPostRevision(int postId) async {
    try {
      final response = await _dio.get('/posts/$postId/revisions/latest.json');
      return PostRevision.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}
