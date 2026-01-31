import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class CampusBuilding {
  final String id;
  final String name;
  final String description;
  final double lat;
  final double lng;

  CampusBuilding({
    required this.id,
    required this.name,
    required this.description,
    required this.lat,
    required this.lng,
  });

  factory CampusBuilding.fromJson(Map<String, dynamic> json) {
    return CampusBuilding(
      id: json['id'] as String,
      name: json['name'] as String,
      description: (json['description'] ?? '') as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }
}

class CampusData {
  final List<CampusBuilding> buildings;

  CampusData({required this.buildings});

  /// ✅ Load from assets where JSON is a LIST, not a MAP
  static Future<CampusData> loadFromAssets() async {
    final raw = await rootBundle.loadString('assets/campus_data.json');

    // JSON FORMAT:
    // [
    //   { "id": "...", "name": "...", ... },
    //   { ... }
    // ]
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;

    final buildings = decoded
        .map((e) => CampusBuilding.fromJson(e as Map<String, dynamic>))
        .toList();

    return CampusData(buildings: buildings);
  }
}
