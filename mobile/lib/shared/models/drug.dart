/// Shared domain model: Drug.
library aph_mobile.shared.models.drug;

import 'package:equatable/equatable.dart';

/// A pharmaceutical drug / product.
class Drug extends Equatable {
  final String id;
  final String name;
  final String? arabicName;
  final String? genericName;
  final String? manufacturer;
  final String? category;
  final double? price;
  final bool available;
  final String? imageUrl;
  final DateTime? createdAt;

  const Drug({
    required this.id,
    required this.name,
    this.arabicName,
    this.genericName,
    this.manufacturer,
    this.category,
    this.price,
    this.available = false,
    this.imageUrl,
    this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        arabicName,
        genericName,
        manufacturer,
        category,
        price,
        available,
        imageUrl,
        createdAt,
      ];

  factory Drug.fromJson(Map<String, dynamic> json) {
    return Drug(
      id: json['id'] as String,
      name: json['name'] as String,
      arabicName: json['arabic_name'] as String?,
      genericName: json['generic_name'] as String?,
      manufacturer: json['manufacturer'] as String?,
      category: json['category'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      available: json['available'] as bool? ?? false,
      imageUrl: json['image_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'arabic_name': arabicName,
      'generic_name': genericName,
      'manufacturer': manufacturer,
      'category': category,
      'price': price,
      'available': available,
      'image_url': imageUrl,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
