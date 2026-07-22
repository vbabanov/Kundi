import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/home_gamification_metrics.dart';
import 'lessons_controller.dart';

final homeGamificationMetricsProvider =
    Provider.family<AsyncValue<HomeGamificationMetrics>, DateTime>(
  (ref, now) {
    final lessonsState = ref.watch(lessonsControllerProvider);
    return lessonsState.whenData(
      (lessons) => HomeGamificationMetrics.fromLessons(
        lessons: lessons,
        now: now,
      ),
    );
  },
);
