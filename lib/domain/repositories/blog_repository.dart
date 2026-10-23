import '../models/blog.dart';

abstract interface class BlogRepository {
  Future<ComposeBlogDetail> fetchBlog(int id);
}
