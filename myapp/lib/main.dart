import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:http/http.dart' as http;

void main() {
  runApp(const SmartCompanionApp());
}

class SmartCompanionApp extends StatelessWidget {
  const SmartCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Companion',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: const CapturePage(),
    );
  }
}

class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  File? _photo;
  Position? _pos;
  String? _address;
  Map<String, dynamic>? _weather;
  bool _busy = false;

  // ---------- CAMERA ----------
  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.camera);
    if (x != null && mounted) setState(() => _photo = File(x.path));
  }

  // ---------- LOCATION + ADDRESS ----------
  Future<void> _getLocationAndAddress() async {
    // ensure services + permissions
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    final p = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
    final placemarks = await geocoding.placemarkFromCoordinates(
      p.latitude,
      p.longitude,
    );
    final m = placemarks.first;

    final parts = <String>[
      if ((m.name ?? '').isNotEmpty) m.name!,
      if ((m.street ?? '').isNotEmpty) m.street!,
      if ((m.locality ?? '').isNotEmpty) m.locality!,
      if ((m.administrativeArea ?? '').isNotEmpty) m.administrativeArea!,
      if ((m.postalCode ?? '').isNotEmpty) m.postalCode!,
      if ((m.country ?? '').isNotEmpty) m.country!,
    ];

    setState(() {
      _pos = p;
      _address = parts.join(', ');
    });
  }

  // ---------- WEATHER (Open-Meteo, no API key) ----------
  Future<void> _fetchWeather() async {
    if (_pos == null) return;
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${_pos!.latitude}&longitude=${_pos!.longitude}&current_weather=true',
    );
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      setState(() {
        _weather =
            (data['current_weather'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Weather error: ${res.statusCode}')),
        );
      }
    }
  }

  // ---------- COMBINED ACTION ----------
  Future<void> _doAll() async {
    setState(() {
      _busy = true;
      _address = null;
      _weather = null;
    });
    try {
      if (_photo == null) await _pickFromCamera();
      await _getLocationAndAddress();
      await _fetchWeather();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- "UPLOAD" (no Firebase, just a snackbar) ----------
  Future<void> _uploadToFirebase() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Upload skipped (Firebase not required for this assignment).',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _weather;
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Companion')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Photo preview
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_photo!, height: 220, fit: BoxFit.cover),
            )
          else
            Container(
              height: 220,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: const Text('No photo yet'),
            ),
          const SizedBox(height: 16),

          // Capture + Locate + Weather
          FilledButton.icon(
            onPressed: _busy ? null : _doAll,
            icon: const Icon(Icons.my_location),
            label: const Text('Capture • Locate • Weather'),
          ),

          const SizedBox(height: 16),

          // Address tile
          if (_pos != null)
            ListTile(
              leading: const Icon(Icons.place),
              title: Text(
                'Lat ${_pos!.latitude.toStringAsFixed(6)} • '
                'Lon ${_pos!.longitude.toStringAsFixed(6)}',
              ),
              subtitle: Text(_address ?? 'Resolving address…'),
            ),

          // Weather tile
          if (w != null && w.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.thermostat),
              title: Text(
                '${w['temperature']}°C  •  wind ${w['windspeed']} km/h',
              ),
              subtitle: Text('At ${w['time']} • dir ${w['winddirection']}°'),
              trailing: const Icon(Icons.cloud),
            ),
          ],

          const SizedBox(height: 12),

          // "Upload" (no-op)
          FilledButton.icon(
            onPressed: (_photo != null && _pos != null && !_busy)
                ? _uploadToFirebase
                : null,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Upload (optional)'),
          ),
        ],
      ),

      // Quick camera FAB
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _pickFromCamera,
        icon: const Icon(Icons.photo_camera),
        label: const Text('Camera'),
      ),
    );
  }
}
