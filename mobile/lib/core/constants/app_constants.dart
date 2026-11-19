/// Design tokens and constants for the APH brand identity.
library aph_mobile.core.constants;

import 'package:flutter/material.dart';

/// Brand colors (APH design palette).
class AppColors {
  AppColors._();

  // Deep Navy: #102A43
  static const Color deepNavy = Color(0xFF102A43);
  // Medical Blue: #168AAD
  static const Color medicalBlue = Color(0xFF168AAD);
  // Turquoise: #20B8B0
  static const Color turquoise = Color(0xFF20B8B0);
  // White: #FFFFFF
  static const Color white = Color(0xFFFFFFFF);
  // Soft Background: #F4F7FA
  static const Color softBackground = Color(0xFFF4F7FA);
  // Success Green: #249B78
  static const Color successGreen = Color(0xFF249B78);

  // Semantic
  static const Color primary = deepNavy;
  static const Color surface = white;
  static const Color background = softBackground;
  static const Color onPrimary = white;
  static const Color error = Color(0xFFB3261E);
}

/// Route names.
class AppRoutes {
  AppRoutes._();
  static const String home = '/';
  static const String login = '/login';
  static const String drugSearch = '/drug-search';
  static const String drugDetails = '/drug-details';
  static const String settings = '/settings';
}

/// API / feature constants.
class AppConstants {
  AppConstants._();
  static const String appTitle = 'Abdulmajeedpharma';
  static const String appShortName = 'APH';
  static const String defaultLocale = 'ar';
  static const List<String> supportedLocales = ['ar', 'en'];
}
