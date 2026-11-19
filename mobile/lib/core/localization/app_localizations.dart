/// Localization (i18n / l10n) — Arabic (Yemen) and English with RTL/LTR support.
library aph_mobile.core.localization;

import 'package:flutter/material.dart';

/// AppLocalizations provides translated strings for the UI.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const List<Locale> supportedLocales = [Locale('ar', 'YE'), Locale('en', 'US')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static List<LocalizationsDelegate<AppLocalizations>> get delegates => [delegate];

  String get title => locale.languageCode == 'ar' ? 'أبدي اماجيد فارما' : 'Abdulmajeedpharma';
  String get home => locale.languageCode == 'ar' ? 'الرئيسية' : 'Home';
  String get search => locale.languageCode == 'ar' ? 'بحث' : 'Search';
  String get settings => locale.languageCode == 'ar' ? 'الإعدادات' : 'Settings';
  String get login => locale.languageCode == 'ar' ? 'تسجيل الدخول' : 'Login';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any(
        (supported) => supported.languageCode == locale.languageCode,
      );

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(covariant _AppLocalizationsDelegate old) => false;
}
