enum HomeInsightKind { studyTip, didYouKnow }

enum HomeInsightGradeBand { primary, middle, senior }

class HomeInsight {
  const HomeInsight({
    required this.text,
    required this.kind,
    required this.locale,
    required this.contentId,
    required this.catalogVersion,
    required this.gradeBand,
    required this.rephrased,
    required this.isLocalFallback,
  });

  final String text;
  final HomeInsightKind kind;
  final String locale;
  final String contentId;
  final int catalogVersion;
  final HomeInsightGradeBand gradeBand;
  final bool rephrased;
  final bool isLocalFallback;

  factory HomeInsight.fromJson(Map<String, dynamic> json) {
    final kind = switch (json['kind']) {
      'study_tip' => HomeInsightKind.studyTip,
      'did_you_know' => HomeInsightKind.didYouKnow,
      _ => throw const FormatException('unsupported home insight kind'),
    };
    final gradeBand = switch (json['grade_band']) {
      'primary' => HomeInsightGradeBand.primary,
      'middle' => HomeInsightGradeBand.middle,
      'senior' => HomeInsightGradeBand.senior,
      _ => throw const FormatException('unsupported home insight grade band'),
    };
    final text = (json['text'] as String?)?.trim() ?? '';
    final locale = (json['locale'] as String?)?.trim() ?? '';
    final contentId = (json['content_id'] as String?)?.trim() ?? '';
    final catalogVersion = json['catalog_version'] as int? ?? 0;
    if (text.isEmpty ||
        text.runes.length > 220 ||
        locale != 'ru' && locale != 'kk' ||
        contentId.isEmpty ||
        catalogVersion < 1 ||
        text.toLowerCase().contains(RegExp(r'https?://|www\.'))) {
      throw const FormatException('invalid home insight payload');
    }
    return HomeInsight(
      text: text,
      kind: kind,
      locale: locale,
      contentId: contentId,
      catalogVersion: catalogVersion,
      gradeBand: gradeBand,
      rephrased: json['rephrased'] == true,
      isLocalFallback: false,
    );
  }

  factory HomeInsight.localFallback({
    required String locale,
    required int gradeLevel,
  }) {
    final band = gradeBandFor(gradeLevel);
    final text = switch ((locale, band)) {
      ('kk', HomeInsightGradeBand.primary) =>
        'Тапсырманы асықпай оқып, бір түсінікті қадамнан баста.',
      ('kk', HomeInsightGradeBand.middle) =>
        'Ережені өз сөзіңмен түсіндіріп көр — түсінбеген жерді байқау оңайырақ.',
      ('kk', HomeInsightGradeBand.senior) =>
        'Шешуге кіріспес бұрын берілгендер мен белгісіздерді жазып ал.',
      ('ru', HomeInsightGradeBand.primary) =>
        'Прочитай задание не спеша и начни с одного понятного шага.',
      ('ru', HomeInsightGradeBand.middle) =>
        'Попробуй объяснить правило своими словами — так легче заметить пробел.',
      _ => 'Перед решением выпиши данные и неизвестные.',
    };
    return HomeInsight(
      text: text,
      kind: HomeInsightKind.studyTip,
      locale: locale,
      contentId: 'local_${band.name}_v1',
      catalogVersion: 1,
      gradeBand: band,
      rephrased: false,
      isLocalFallback: true,
    );
  }
}

HomeInsightGradeBand gradeBandFor(int gradeLevel) {
  if (gradeLevel >= 1 && gradeLevel <= 4) {
    return HomeInsightGradeBand.primary;
  }
  if (gradeLevel >= 9) return HomeInsightGradeBand.senior;
  return HomeInsightGradeBand.middle;
}
