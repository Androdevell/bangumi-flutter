import '../models/blog.dart';
import '../../core/paged.dart';

abstract interface class BlogRepository {
  Future<ComposeBlogDetail> fetchBlog(int id);
}

abstract interface class BlogPhotoRepository {
  Future<Paged<ComposeBlogPhoto>> fetchBlogPhotos(int id, {int offset = 0});
}
