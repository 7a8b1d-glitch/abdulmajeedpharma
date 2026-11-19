/// Shared utilities and extensions.
library aph_mobile.core.utils;

/// Formats a price for display.
String formatPrice(double amount, {String currency = 'YER'}) {
  return '$currency ${amount.toStringAsFixed(0)}';
}

/// Returns a display label for drug availability.
String availabilityLabel(bool available) => available ? 'Available' : 'Out of stock';

/// Extension to check if a string is blank.
extension StringExt on String? {
  bool get isBlank => this == null || this!.trim().isEmpty;
}
