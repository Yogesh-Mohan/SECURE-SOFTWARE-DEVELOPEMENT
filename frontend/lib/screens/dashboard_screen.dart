import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import '../api_service.dart';
import '../fcm_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
  with WidgetsBindingObserver {
  String name = "";
  String role = "";
  bool isEmergencyActive = false;
  String trackingStatus = "Checking location...";
  double? lat;
  double? lon;
  String? _userId;

  String? _lastAlertMessage;
  DateTime? _lastAlertTime;
  bool _isLoggingOut = false;
  bool _voiceNotificationsEnabled = true;

  Timer? _locationTimer;
  Timer? _proximityTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertsSubscription;
  String? _lastAlertDocId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    await _loadUserData();
    await _ensureAllPermissions();
    await FcmService.initialize();
    await _startTrackingIfAllowed();
  }

  Future<void> _ensureAllPermissions() async {
    // 1. Request Notification Permission
    final notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      final result = await Permission.notification.request();
      if (result.isDenied || result.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Notification permission is required for emergency alerts!'),
              backgroundColor: AppColors.primaryRed,
              action: SnackBarAction(
                label: 'SETTINGS',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }
    }

    // 2. Request Location Permission
    final locationStatus = await Permission.location.status;
    if (!locationStatus.isGranted) {
      final result = await Permission.location.request();
      if (result.isDenied || result.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission is required for tracking and alerts!'),
              backgroundColor: AppColors.primaryRed,
              action: SnackBarAction(
                label: 'SETTINGS',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      name = prefs.getString('name') ?? "User";
      role = prefs.getString('role') ?? "public";
      isEmergencyActive = prefs.getBool('emergency_active') ?? false;
      _userId = prefs.getString('user_id');
      _voiceNotificationsEnabled = prefs.getBool('voice_notifications_enabled') ?? true;

      _lastAlertDocId = prefs.getString('last_alert_doc_id');
      _lastAlertMessage = prefs.getString('last_alert_message');
      final lastAlertMs = prefs.getInt('last_alert_ms');
      _lastAlertTime = lastAlertMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastAlertMs)
          : null;

      if (role == 'driver' && isEmergencyActive) {
        _startProximityScanner();
      }
    });

    _startAlertListenerIfNeeded();
  }

  void _startAlertListenerIfNeeded() {
    _alertsSubscription?.cancel();

    if (role != 'public') {
      return;
    }

    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    _alertsSubscription = FirebaseFirestore.instance
        .collection('alerts')
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) async {
      // Only process ADDED documents (new alerts)
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) {
          continue;
        }

        final doc = change.doc;
        if (doc.id == _lastAlertDocId) {
          continue;
        }

        _lastAlertDocId = doc.id;
        final data = doc.data() ?? {};
        final message = (data['message'] ?? FcmService.emergencyMessage).toString();

        debugPrint('🚨 New alert received: $message (doc: ${doc.id})');

        final now = DateTime.now();
        if (mounted) {
          setState(() {
            _lastAlertMessage = message;
            _lastAlertTime = now;
          });
        }

        // Show local push notification
        await FcmService.showEmergencyLocalNotification(message: message);

        // Show in-app snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(child: Text(message)),
                ],
              ),
              backgroundColor: AppColors.primaryRed,
              duration: const Duration(seconds: 5),
            ),
          );
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_alert_doc_id', doc.id);
        await prefs.setString('last_alert_message', message);
        await prefs.setInt('last_alert_ms', now.millisecondsSinceEpoch);

        // Only process the latest new alert, break after first
        break;
      }
    }, onError: (e) {
      debugPrint('Alert listener error: $e');
    });
  }

  Future<void> _checkLatestAlertOnce() async {
    if (role != 'public') {
      return;
    }

    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenId = prefs.getString('last_alert_doc_id');

      final snapshot = await FirebaseFirestore.instance
          .collection('alerts')
          .where('user_id', isEqualTo: userId)
          .limit(5)
          .get();

      if (snapshot.docs.isEmpty) {
        return;
      }

      // Sort by timestamp client-side to find the latest
      final docs = snapshot.docs.toList();
      docs.sort((a, b) {
        final aTime = (a.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
        final bTime = (b.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
        return bTime.compareTo(aTime); // descending
      });

      final doc = docs.first;
      if (doc.id == lastSeenId) {
        return;
      }

      _lastAlertDocId = doc.id;
      final message =
          (doc.data()['message'] ?? FcmService.emergencyMessage).toString();

      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _lastAlertMessage = message;
          _lastAlertTime = now;
        });
      }

      await FcmService.showEmergencyLocalNotification(message: message);
      await prefs.setString('last_alert_doc_id', doc.id);
      await prefs.setString('last_alert_message', message);
      await prefs.setInt('last_alert_ms', now.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Failed to check latest alert: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLatestAlertOnce();
    }
  }

  Future<void> _startTrackingIfAllowed() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() => trackingStatus = "Location services disabled");
      await Geolocator.openLocationSettings();
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() => trackingStatus = "Location denied");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to receive nearby ambulance alerts.')),
        );
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => trackingStatus = "Location permanently denied");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable location permission from Settings to continue live safety alerts.')),
      );
      await Geolocator.openAppSettings();
      return;
    } 

    if (!mounted) return;
    setState(() => trackingStatus = "Getting location...");

    _locationTimer?.cancel();
    await _fetchAndUpdateLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _fetchAndUpdateLocation();
    });
  }

  Future<void> _fetchAndUpdateLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          lat = position.latitude;
          lon = position.longitude;
          trackingStatus = "Live (Foreground)";
        });
      }

      await ApiService.updateLocation(position.latitude, position.longitude);
    } catch (e) {
      debugPrint("Location error: $e");
      if (mounted) {
        setState(() => trackingStatus = "Location retrying..." );
      }
    }
  }

  Future<void> _toggleEmergency() async {
    final nextState = !isEmergencyActive;

    // Push latest known location before enabling emergency for faster first alert.
    if (nextState && lat != null && lon != null) {
      await ApiService.updateLocation(lat!, lon!);
    }

    final updated = await ApiService.toggleEmergency(nextState);
    if (!mounted) return;

    if (!updated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Emergency update failed")));
      return;
    }

    setState(() {
      isEmergencyActive = nextState;
      trackingStatus = isEmergencyActive
          ? "Emergency active"
          : "Tracking active";
    });

    if (isEmergencyActive) {
      _startProximityScanner();
    } else {
      _proximityTimer?.cancel();
    }
  }

  Future<void> _toggleVoiceNotifications() async {
    final newValue = !_voiceNotificationsEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_notifications_enabled', newValue);

    if (mounted) {
      setState(() {
        _voiceNotificationsEnabled = newValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voice alerts ${newValue ? 'enabled' : 'disabled'}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _startProximityScanner() {
    _proximityTimer?.cancel();
    _runAmbulanceAlertCycle(forceImmediate: true);
    _proximityTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _runAmbulanceAlertCycle();
    });
  }

  Future<void> _runAmbulanceAlertCycle({bool forceImmediate = false}) async {
    try {
      await ApiService.processAmbulanceAlerts(forceImmediate: forceImmediate);
    } catch (e) {
      debugPrint('Ambulance alert cycle failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertsSubscription?.cancel();
    _locationTimer?.cancel();
    _proximityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              if (_isLoggingOut) {
                return;
              }

              _isLoggingOut = true;
              _locationTimer?.cancel();
              _proximityTimer?.cancel();
              await _alertsSubscription?.cancel();
              _alertsSubscription = null;

              if (role == 'driver' && isEmergencyActive) {
                await ApiService.toggleEmergency(false);
              }

              await FcmService.dispose();

              await AuthService.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUserHeader(),
            const SizedBox(height: 16),
            _buildTrackingStatusCard(),
            const SizedBox(height: 30),
            _buildLocationCard(),
            const SizedBox(height: 40),
            if (role == 'driver') _buildDriverEmergencyPanel(),
            if (role == 'public') _buildPublicStatusPanel(),
            const SizedBox(height: 40),
            _buildSettingsPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Welcome back,",
          style: TextStyle(color: AppColors.primaryBlue.withValues(alpha: 0.7)),
        ),
        Text(
          name,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryBlue,
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: role == 'driver'
                ? AppColors.primaryRed
                : AppColors.accentBlue,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            role.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.primaryRed),
              const SizedBox(width: 10),
              const Text(
                "Current Status",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Spacer(),
              const Icon(Icons.wifi_tethering, color: Colors.green),
              const SizedBox(width: 5),
              const Text(
                "Live",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCoordItem("LATITUDE", lat?.toStringAsFixed(6) ?? "---"),
              _buildCoordItem("LONGITUDE", lon?.toStringAsFixed(6) ?? "---"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingStatusCard() {
    final isIssue =
        trackingStatus.contains('denied') ||
        trackingStatus.contains('disabled') ||
        trackingStatus.contains('retrying');
    final isEmergency = trackingStatus.contains('Emergency');

    final statusColor = isIssue
        ? Colors.orange
        : (isEmergency ? AppColors.primaryRed : Colors.green);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.track_changes, size: 18, color: statusColor),
          const SizedBox(width: 8),
          const Text(
            "Tracking:",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              trackingStatus,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildDriverEmergencyPanel() {
    return Center(
      child: Column(
        children: [
          const Text(
            "EMERGENCY CONTROLS",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 15),
          GestureDetector(
            onTap: _toggleEmergency,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isEmergencyActive
                    ? Colors.white
                    : AppColors.primaryRed,
                border: Border.all(color: AppColors.primaryRed, width: 8),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryRed.withValues(alpha: 0.3),
                    blurRadius: isEmergencyActive ? 30 : 10,
                    spreadRadius: isEmergencyActive ? 10 : 2,
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isEmergencyActive
                          ? Icons.warning_rounded
                          : Icons.radio_button_checked,
                      size: 50,
                      color: isEmergencyActive
                          ? AppColors.primaryRed
                          : Colors.white,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isEmergencyActive
                          ? "STOP\nEMERGENCY"
                          : "START\nEMERGENCY",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isEmergencyActive
                            ? AppColors.primaryRed
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isEmergencyActive
                ? "Broadcasting live to traffic systems!"
                : "Standby mode - Ready for calls",
            style: TextStyle(
              color: isEmergencyActive
                  ? AppColors.primaryRed
                  : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicStatusPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield, color: AppColors.accentBlue),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Public mode active. Your location is being securely shared for emergency response.",
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_lastAlertMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Last alert: ${_lastAlertMessage!}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_lastAlertTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Received: ${_lastAlertTime!.toLocal().toString().split('.').first}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.settings, color: AppColors.primaryBlue),
              SizedBox(width: 10),
              Text(
                "Settings",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Voice Alerts",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Speak emergency alerts aloud",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              Switch(
                value: _voiceNotificationsEnabled,
                onChanged: (_) => _toggleVoiceNotifications(),
                activeThumbColor: AppColors.primaryBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
