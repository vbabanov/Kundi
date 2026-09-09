import 'home_insight.dart';

abstract class HomeInsightRepository {
  Future<HomeInsight> getInsight({required String locale});
}
