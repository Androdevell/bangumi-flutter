import '../../core/community_models.dart';

enum CommentOrder { oldest, newest, likes }

List<CommunityReply> sortedComments(
  List<CommunityReply> items,
  CommentOrder order,
) {
  final result = [...items];
  int time(CommunityReply a, CommunityReply b) =>
      (a.createdAt?.millisecondsSinceEpoch ?? a.id).compareTo(
        b.createdAt?.millisecondsSinceEpoch ?? b.id,
      );
  int votes(CommunityReply r) => r.reactions.fold(0, (n, e) => n + e.count);
  result.sort((a, b) {
    final comparison = switch (order) {
      CommentOrder.oldest => time(a, b),
      CommentOrder.newest => time(b, a),
      CommentOrder.likes => votes(b).compareTo(votes(a)),
    };
    return comparison == 0 ? a.id.compareTo(b.id) : comparison;
  });
  return result;
}
