import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/home_insight/domain/home_insight.dart';

void main() {
  test('local fallback is immediate, localized and grade-aware', () {
    final primaryRu = HomeInsight.localFallback(locale: 'ru', gradeLevel: 2);
    final middleKk = HomeInsight.localFallback(locale: 'kk', gradeLevel: 7);
    final seniorRu = HomeInsight.localFallback(locale: 'ru', gradeLevel: 11);

    expect(primaryRu.isLocalFallback, isTrue);
    expect(primaryRu.locale, 'ru');
    expect(primaryRu.gradeBand, HomeInsightGradeBand.primary);
    expect(primaryRu.text, contains('одного понятного шага'));
    expect(middleKk.locale, 'kk');
    expect(middleKk.gradeBand, HomeInsightGradeBand.middle);
    expect(middleKk.text, contains('өз сөзіңмен'));
    expect(seniorRu.gradeBand, HomeInsightGradeBand.senior);
  });

  test('server payload validation keeps only supported bounded content', () {
    final insight = HomeInsight.fromJson(const <String, dynamic>{
      'text': 'Қысқа кеңес.',
      'kind': 'study_tip',
      'locale': 'kk',
      'content_id': 'tip_v1',
      'catalog_version': 1,
      'grade_band': 'middle',
      'rephrased': true,
    });

    expect(insight.text, 'Қысқа кеңес.');
    expect(insight.rephrased, isTrue);
    expect(insight.isLocalFallback, isFalse);
    expect(
      () => HomeInsight.fromJson(const <String, dynamic>{
        'text': 'https://example.com',
        'kind': 'did_you_know',
        'locale': 'ru',
        'content_id': 'unsafe',
        'catalog_version': 1,
        'grade_band': 'middle',
      }),
      throwsFormatException,
    );
  });
}
