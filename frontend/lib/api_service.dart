import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const int _alertCooldownSeconds = 30;

  static CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  static CollectionReference<Map<String, dynamic>> get _ambulance =>
      _db.collection('ambulance');
  static CollectionReference<Map<String, dynamic>> get _alerts =>
      _db.collection('alerts');

  static Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  static Future<Map<String, dynamic>> register(
    String name,
    String mobile,
    String password,
    String role,
  ) async {
    try {
      final cleanedName = name.trim();
      final cleanedMobile = mobile.trim();
      final cleanedPassword = password.trim();

      if (cleanedName.isEmpty) {
        return {'detail': 'Name is required'};
      }

      if (cleanedMobile.length < 10) {
        return {'detail': 'Valid mobile number is required'};
      }

      if (cleanedPassword.length < 6) {
        return {'detail': 'Password must be at least 6 characters'};
      }

      final existing = await _users
          .where('mobile', isEqualTo: cleanedMobile)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return {'detail': 'Mobile number already registered'};
      }

      final now = FieldValue.serverTimestamp();
      final userRef = _users.doc();
      await userRef.set({
        'name': cleanedName,
        'mobile': cleanedMobile,
        'password': cleanedPassword,
        'role': role,
        'location': {'lat': 0.0, 'lng': 0.0},
        'is_active': false,
        'createdAt': now,
        'updatedAt': now,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userRef.id);
      await prefs.setString('token', userRef.id);
      await prefs.setString('name', cleanedName);
      await prefs.setString('role', role);

      if (role == 'driver') {
        await _ambulance.doc(userRef.id).set({
          'driverUserId': userRef.id,
          'driverName': cleanedName,
          'status': 'available',
          'is_active': false,
          'location': {'lat': 0.0, 'lng': 0.0},
          'createdAt': now,
          'updatedAt': now,
        });
      }

      return {'message': 'User registered successfully', 'user_id': userRef.id};
    } on FirebaseException catch (e) {
      debugPrint('Registration FirebaseException: code=${e.code}, message=${e.message}');
      return {'detail': 'Registration failed: ${e.message ?? e.code}'};
    } catch (e) {
      debugPrint('Registration exception: $e');
      return {'detail': 'Registration failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> login(
    String mobile,
    String password,
  ) async {
    try {
      final cleanedMobile = mobile.trim();
      final snapshot = await _users
          .where('mobile', isEqualTo: cleanedMobile)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) {
        return {'detail': 'User not found'};
      }

      final userDoc = snapshot.docs.first;
      final userData = userDoc.data();
      if ((userData['password'] ?? '') != password) {
        return {'detail': 'Invalid credentials'};
      }

      final data = {
        'access_token': userDoc.id,
        'user_id': userDoc.id,
        'role': userData['role'] ?? 'public',
        'name': userData['name'] ?? 'User',
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['access_token']);
      await prefs.setString('user_id', data['user_id']);
      await prefs.setString('role', data['role']);
      await prefs.setString('name', data['name']);

      return data;
    } catch (_) {
      return {'detail': 'Login failed'};
    }
  }

  static Future<bool> updateLocation(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final role = prefs.getString('role') ?? 'public';
    final emergencyActive = prefs.getBool('emergency_active') ?? false;
    final name = prefs.getString('name') ?? 'Driver';

    if (userId == null) {
      return false;
    }

    try {
      final now = FieldValue.serverTimestamp();
      await prefs.setDouble('last_lat', lat);
      await prefs.setDouble('last_lng', lon);

      await _users.doc(userId).set({
        'location': {'lat': lat, 'lng': lon},
        'updatedAt': now,
      }, SetOptions(merge: true));

      if (role == 'driver' && emergencyActive) {
        await _ambulance.doc('main').set({
          'driverUserId': userId,
          'driverName': name,
          'is_active': true,
          'status': 'busy',
          'location': {'lat': lat, 'lng': lon},
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggleEmergency(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final role = prefs.getString('role') ?? 'public';
    final name = prefs.getString('name') ?? 'Driver';
    final lastLat = prefs.getDouble('last_lat') ?? 0.0;
    final lastLng = prefs.getDouble('last_lng') ?? 0.0;

    if (userId == null || role != 'driver') {
      return false;
    }

    try {
      final now = FieldValue.serverTimestamp();
      await prefs.setBool('emergency_active', active);

      await _ambulance.doc('main').set({
        'driverUserId': userId,
        'driverName': name,
        'is_active': active,
        'status': active ? 'busy' : 'available',
        'location': {'lat': lastLat, 'lng': lastLng},
        'updatedAt': now,
      }, SetOptions(merge: true));

      if (active) {
        await _alerts.add({
          'userId': userId,
          'ambulanceId': userId,
          'message': 'Emergency mode activated',
          'severity': 'high',
          'status': 'active',
          'createdAt': now,
        });
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> processAmbulanceAlerts() async {
    try {
      final ambulanceDoc = await _ambulance.doc('main').get();
      if (!ambulanceDoc.exists) {
        return;
      }

      final ambulanceData = ambulanceDoc.data();
      if (ambulanceData == null) {
        return;
      }

      final isActive = ambulanceData['is_active'] == true;
      if (!isActive) {
        return;
      }

      final activeDriverUserId = ambulanceData['driverUserId'] as String?;

      final ambulanceLocation = ambulanceData['location'];
      if (ambulanceLocation is! Map<String, dynamic>) {
        return;
      }

      final ambulanceLat = (ambulanceLocation['lat'] as num?)?.toDouble();
      final ambulanceLng = (ambulanceLocation['lng'] as num?)?.toDouble();
      if (ambulanceLat == null || ambulanceLng == null) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final usersSnapshot = await _users.get();
      for (final userDoc in usersSnapshot.docs) {
        if (activeDriverUserId != null && userDoc.id == activeDriverUserId) {
          continue;
        }

        final userData = userDoc.data();
        final userLocation = userData['location'];
        if (userLocation is! Map<String, dynamic>) {
          continue;
        }

        final userLat = (userLocation['lat'] as num?)?.toDouble();
        final userLng = (userLocation['lng'] as num?)?.toDouble();
        if (userLat == null || userLng == null) {
          continue;
        }

        final distanceMeters = _haversineMeters(
          ambulanceLat,
          ambulanceLng,
          userLat,
          userLng,
        );

        if (distanceMeters <= 300) {
          final key = 'last_alert_ms_${userDoc.id}';
          final lastAlertMs = prefs.getInt(key);
          final cooldownMs = _alertCooldownSeconds * 1000;
          final inCooldown =
              lastAlertMs != null && (nowMs - lastAlertMs) < cooldownMs;
          if (inCooldown) {
            continue;
          }

          const message = '🚨 Ambulance coming – move left';
          // Basic alert output for local verification.
          debugPrint('[$distanceMeters m] $message for user ${userDoc.id}');

          await _alerts.add({
            'user_id': userDoc.id,
            'message': message,
            'timestamp': FieldValue.serverTimestamp(),
          });

          await prefs.setInt(key, nowMs);
        }
      }
    } catch (_) {
      // Swallow to keep tracking loop stable.
    }
  }

  static double _haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double degree) {
    return degree * (math.pi / 180.0);
  }
}
