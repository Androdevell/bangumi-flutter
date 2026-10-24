import '../../core/paged.dart';

abstract interface class IndexRepository {
  Future<Map<String, dynamic>> indexInfo(int id);
  Future<Paged<Map<String, dynamic>>> indexEntries(int id, {int offset = 0});
}
