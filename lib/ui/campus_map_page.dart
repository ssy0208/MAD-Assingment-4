import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../src/campus_data.dart';
import '../src/location_helper.dart';

class CampusMapPage extends StatefulWidget {
  const CampusMapPage({super.key});

  @override
  State<CampusMapPage> createState() => _CampusMapPageState();
}

class _CampusMapPageState extends State<CampusMapPage> {
  final Completer<GoogleMapController> _mapController = Completer();

  // ✅ Change this if you want your entrance to be different
  static const LatLng _mainEntrance = LatLng(1.8600, 103.0850);

  String? _mapStyle;
  CampusData? _campusData;

  final Map<String, Marker> _buildingMarkers = {};
  final Set<Polygon> _polygons = {};
  final Set<Circle> _circles = {};
  final Set<Polyline> _polylines = {};

  Position? _currentPosition;
  StreamSubscription<Position>? _posSub;

  final BitmapDescriptor _startIcon =
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  final BitmapDescriptor _endIcon =
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);

  // ✅ Destination chosen by tapping a building marker
  CampusBuilding? _selectedDestination;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _loadCampusData();
    _initLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style_midnight.json');
    if (!mounted) return;
    setState(() => _mapStyle = style);
  }

  Future<void> _loadCampusData() async {
    final data = await CampusData.loadFromAssets();
    if (!mounted) return;

    setState(() {
      _campusData = data;
      _buildingMarkers.clear();

      for (final b in data.buildings) {
        _buildingMarkers[b.id] = Marker(
          markerId: MarkerId(b.id),
          position: LatLng(b.lat, b.lng),
          infoWindow: InfoWindow(
            title: b.name,
            snippet: 'Tap marker to select destination',
          ),
          onTap: () {
            setState(() => _selectedDestination = b);
            _showSnack('Destination selected: ${b.name}');
          },
        );
      }

      // Optional: auto select first building
      if (data.buildings.isNotEmpty) {
        _selectedDestination = data.buildings.first;
      }
    });

    _buildZones();
  }

  void _buildZones() {
    // ✅ Sample polygon boundary (replace with your real boundary points if needed)
    const polygonPoints = <LatLng>[
      LatLng(1.8616, 103.0845),
      LatLng(1.8616, 103.0862),
      LatLng(1.8594, 103.0862),
      LatLng(1.8594, 103.0845),
    ];

    // ✅ Quiet zone: center on PITA if exists, else fallback
    final pita =
        _campusData?.buildings.where((b) => b.id == 'pita').toList() ?? [];
    final circleCenter = pita.isNotEmpty
        ? LatLng(pita.first.lat, pita.first.lng)
        : const LatLng(1.8612, 103.0841);

    setState(() {
      _polygons
        ..clear()
        ..add(
          Polygon(
            polygonId: const PolygonId('boundary'),
            points: polygonPoints,
            strokeWidth: 3,
            strokeColor: Colors.blue,
            fillColor: Colors.blue.withValues(alpha: 0.20),
          ),
        );

      _circles
        ..clear()
        ..add(
          Circle(
            circleId: const CircleId('quiet_zone'),
            center: circleCenter,
            radius: 200,
            strokeWidth: 2,
            strokeColor: Colors.green,
            fillColor: Colors.green.withValues(alpha: 0.20),
          ),
        );
    });
  }

  Future<void> _initLocation() async {
    try {
      final pos = await LocationHelper.determinePosition();
      if (!mounted) return;

      setState(() => _currentPosition = pos);

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _currentPosition = p);
      });
    } catch (e) {
      _showSnack('Location error: $e');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController.complete(controller);
  }

  void _onTapMap(LatLng tapped) {
    // Useful: show nearest building when tap map
    final nearest = _findNearestBuilding(tapped);
    if (nearest == null) {
      _showSnack('No building data loaded.');
      return;
    }

    _showSnack(
      'Tapped: (${tapped.latitude.toStringAsFixed(6)}, ${tapped.longitude.toStringAsFixed(6)})\n'
      'Nearest: ${nearest.name}',
    );
  }

  CampusBuilding? _findNearestBuilding(LatLng point) {
    final data = _campusData;
    if (data == null || data.buildings.isEmpty) return null;

    CampusBuilding best = data.buildings.first;
    double bestDist =
        _haversineMeters(point.latitude, point.longitude, best.lat, best.lng);

    for (final b in data.buildings.skip(1)) {
      final d = _haversineMeters(point.latitude, point.longitude, b.lat, b.lng);
      if (d < bestDist) {
        bestDist = d;
        best = b;
      }
    }
    return best;
  }

  Future<void> _findMe() async {
    if (_currentPosition == null) {
      _showSnack('Current location not ready yet.');
      return;
    }

    final controller = await _mapController.future;
    final target =
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    await controller.animateCamera(CameraUpdate.newLatLngZoom(target, 18));
  }

  // ✅ Fake curved route using quadratic Bezier curve (NO API)
  List<LatLng> _generateCurvedRoute(LatLng start, LatLng end,
      {int points = 40}) {
    final List<LatLng> route = [];

    // Midpoint
    final midLat = (start.latitude + end.latitude) / 2;
    final midLng = (start.longitude + end.longitude) / 2;

    // Curve offset (increase for more curve, decrease for less)
    final curveOffset = 0.0008;

    final controlPoint = LatLng(
      midLat + curveOffset,
      midLng - curveOffset,
    );

    for (int i = 0; i <= points; i++) {
      final t = i / points;

      final lat = math.pow(1 - t, 2) * start.latitude +
          2 * (1 - t) * t * controlPoint.latitude +
          math.pow(t, 2) * end.latitude;

      final lng = math.pow(1 - t, 2) * start.longitude +
          2 * (1 - t) * t * controlPoint.longitude +
          math.pow(t, 2) * end.longitude;

      route.add(LatLng(lat.toDouble(), lng.toDouble()));
    }

    return route;
  }

  Future<void> _navigateToSelectedBuilding() async {
    if (_currentPosition == null) {
      _showSnack('Current location not ready yet.');
      return;
    }

    if (_selectedDestination == null) {
      _showSnack('Please tap a building marker to choose destination.');
      return;
    }

    final start =
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final end = LatLng(_selectedDestination!.lat, _selectedDestination!.lng);

    final routePoints = _generateCurvedRoute(start, end);

    setState(() {
      _polylines
        ..clear()
        ..add(
          Polyline(
            polylineId: const PolylineId('fake_route'),
            points: routePoints,
            width: 6,
            color: Colors.orange,
            geodesic: true,
          ),
        );

      _buildingMarkers['__start'] = Marker(
        markerId: const MarkerId('start_marker'),
        position: start,
        icon: _startIcon,
        infoWindow: const InfoWindow(title: 'You (Start)'),
      );

      _buildingMarkers['__end'] = Marker(
        markerId: const MarkerId('end_marker'),
        position: end,
        icon: _endIcon,
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: _selectedDestination!.name,
        ),
      );
    });

    final controller = await _mapController.future;
    final bounds = _boundsFromTwoPoints(start, end);

    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (_) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(end, 17));
    }
  }

  void _clearRoute() {
    setState(() {
      _polylines.clear();
      _buildingMarkers.remove('__start');
      _buildingMarkers.remove('__end');
    });
    _showSnack('Route cleared');
  }

  LatLngBounds _boundsFromTwoPoints(LatLng a, LatLng b) {
    return LatLngBounds(
      southwest: LatLng(
        math.min(a.latitude, b.latitude),
        math.min(a.longitude, b.longitude),
      ),
      northeast: LatLng(
        math.max(a.latitude, b.latitude),
        math.max(a.longitude, b.longitude),
      ),
    );
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double d) => d * (math.pi / 180.0);

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final allMarkers = <Marker>{..._buildingMarkers.values};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Explorer'),
        actions: [
          IconButton(
            onPressed: _clearRoute,
            icon: const Icon(Icons.clear),
            tooltip: 'Clear route',
          ),
        ],
      ),
      body: Column(
        children: [
          // ✅ Small destination info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Text(
              _selectedDestination == null
                  ? 'Tap a building marker to choose destination.'
                  : 'Destination: ${_selectedDestination!.name}',
            ),
          ),
          Expanded(
            child: GoogleMap(
              style: _mapStyle,
              initialCameraPosition: const CameraPosition(
                target: _mainEntrance,
                zoom: 17,
              ),
              onMapCreated: _onMapCreated,
              markers: allMarkers,
              polygons: _polygons,
              circles: _circles,
              polylines: _polylines,
              myLocationEnabled: _currentPosition != null,
              myLocationButtonEnabled: false,
              onTap: _onTapMap,
              compassEnabled: true,
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'findme',
            onPressed: _findMe,
            label: const Text('Find Me'),
            icon: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'navigate',
            onPressed: _navigateToSelectedBuilding,
            label: const Text('Navigate'),
            icon: const Icon(Icons.alt_route),
          ),
        ],
      ),
    );
  }
}
