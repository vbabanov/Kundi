class AcademicYearWindow {
  const AcademicYearWindow({
    required this.startUtc,
    required this.endUtc,
  });

  final DateTime startUtc;
  final DateTime endUtc;

  String get windowFrom => _formatYmd(startUtc);

  String get windowTo => _formatYmd(endUtc);

  static AcademicYearWindow forNowUtc(DateTime nowUtc) {
    final normalizedNow = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final schoolYearStartYear =
        normalizedNow.month >= 9 ? normalizedNow.year : normalizedNow.year - 1;
    final start = DateTime.utc(schoolYearStartYear, 9, 1);
    return AcademicYearWindow(startUtc: start, endUtc: normalizedNow);
  }

  static String _formatYmd(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
