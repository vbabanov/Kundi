import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_ru.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsRu();

  String get localeName {
    final localized =
        Localizations.of<AppLocalizations>(this, AppLocalizations);
    return localized?.localeName ?? 'ru';
  }

  void _ensureDateSymbols() {
    // Registration from date_symbol_data_local happens synchronously even
    // though the API returns a completed Future. main() also awaits RU/KK
    // initialization; this keeps isolated widget surfaces deterministic.
    initializeDateFormatting(localeName);
  }

  String formatShortWeekday(DateTime value) {
    _ensureDateSymbols();
    return _capitalize(
        DateFormat.E(localeName).format(value).replaceAll('.', ''));
  }

  String formatShortWeekdayNumber(int weekday) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) return '';
    return formatShortWeekday(DateTime(2024, 1, weekday));
  }

  String formatShortMonth(DateTime value) {
    _ensureDateSymbols();
    return DateFormat.MMM(localeName).format(value).replaceAll('.', '');
  }

  String formatDayMonth(DateTime value) {
    _ensureDateSymbols();
    return DateFormat.MMMd(localeName).format(value);
  }

  String formatMonth(DateTime value) {
    _ensureDateSymbols();
    return DateFormat.MMMM(localeName).format(value);
  }

  String formatFullDate(DateTime value) {
    _ensureDateSymbols();
    final formatted = DateFormat('EEEE, d MMMM', localeName).format(value);
    if (formatted.isEmpty) return formatted;
    return '${formatted[0].toUpperCase()}${formatted.substring(1)}';
  }
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
