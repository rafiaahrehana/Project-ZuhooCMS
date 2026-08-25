import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/kb/kb_models.dart';

/// The knowledge base is read on a phone while somebody waits, so the two
/// things that matter are that a row says something useful before it is opened
/// and that the keywords parse.
void main() {
  KbArticle article({String? summary, String? content, String? keywords}) =>
      KbArticle(
        id: 1,
        title: 'Resetting a client portal password',
        status: KbArticleStatus.published,
        viewCount: 12,
        helpfulCount: 3,
        summary: summary,
        content: content,
        keywords: keywords,
      );

  group('preview', () {
    test('prefers the summary when there is one', () {
      expect(
        article(summary: 'Send them the link.', content: 'Long body…').preview,
        'Send them the link.',
      );
    });

    test('falls back to the body, collapsed onto one line', () {
      expect(
        article(content: 'First line.\n\n  Second   line.').preview,
        'First line. Second line.',
      );
    });

    test('clips a long body rather than returning all of it', () {
      final long = article(content: 'x' * 400).preview!;
      expect(long.length, lessThan(200));
      expect(long, endsWith('…'));
    });

    test('is null when there is nothing to show', () {
      expect(article().preview, isNull);
      expect(article(summary: '   ', content: '  ').preview, isNull);
    });
  });

  group('keywordList', () {
    test('splits the comma-separated string the backend stores', () {
      expect(
        article(keywords: 'portal, password ,reset').keywordList,
        ['portal', 'password', 'reset'],
      );
    });

    test('is empty rather than a list of blanks', () {
      expect(article(keywords: ' , , ').keywordList, isEmpty);
      expect(article().keywordList, isEmpty);
    });
  });
}
