import 'package:bangumi_flutter/widgets/bangumi_rich_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves current Bangumi sticker families', () {
    expect(
      bangumiEmojiUrl('bgm500'),
      'https://lain.bgm.tv/img/smiles/tv_500/bgm_500.gif',
    );
    expect(
      bangumiEmojiUrl('bgm504'),
      'https://lain.bgm.tv/img/smiles/tv_500/bgm_504.png',
    );
    expect(
      bangumiEmojiUrl('musume_15'),
      'https://lain.bgm.tv/img/smiles/musume/musume_15.gif',
    );
    expect(
      bangumiEmojiUrl('blake_118'),
      'https://lain.bgm.tv/img/smiles/blake/blake_118.gif',
    );
  });

  testWidgets('renders sized image BBCode and escaped URLs', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BangumiRichText(
            r'[img=224,126]https://lain.bgm.tv/pic/photo/l/19/57/138463\_iJH12.jpg[/img]',
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(
      image.imageUrl,
      'https://lain.bgm.tv/pic/photo/l/19/57/138463_iJH12.jpg',
    );
    expect(find.textContaining('[img='), findsNothing);
  });

  testWidgets('renders character stickers inside comments', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BangumiRichText('庆祝(musume_15)(blake_03)')),
      ),
    );

    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .map((image) => image.imageUrl);
    expect(
      images,
      containsAll(<String>[
        'https://lain.bgm.tv/img/smiles/musume/musume_15.gif',
        'https://lain.bgm.tv/img/smiles/blake/blake_03.gif',
      ]),
    );
  });
}
