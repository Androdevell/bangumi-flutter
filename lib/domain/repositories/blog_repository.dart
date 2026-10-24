import '../models/blog.dart';
import '../../core/paged.dart';
import '../../app/state/session_scope.dart';

abstract interface class BlogCommentRepository {
  Future<void> createBlogComment(
    int id,
    String content, {
    required SessionScope scope,
    int replyTo = 0,
  });
  void invalidateBlogComments(int id);
}

abstract interface class BlogRepository {
  Future<ComposeBlogDetail> fetchBlog(int id);
}

abstract interface class BlogPhotoRepository {
  Future<Paged<ComposeBlogPhoto>> fetchBlogPhotos(int id, {int offset = 0});
}
