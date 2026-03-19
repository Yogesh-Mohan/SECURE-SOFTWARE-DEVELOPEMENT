import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; 
// import 'package:flutter_background_service/flutter_background_service.dart'; // TODO: Re-enable after fixing foreground notification
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../api_service.dart';
import '../fcm_service.dart';
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
  String? _fcmToken;
  String? _userId;

  String? _lastAlertMessage;
  DateTime? _lastAlertTime;

  Timer? _locationTimer;
  Timer? _proximityTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertsSubscription;
  String? _lastAlertDocId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadUserData().then((_) async {
      String? token = await FcmService.initialize();
      if (mounted) {
        setState(() {
          _fcmToken = token;
        });
      }
    });
    _startTrackingIfAllowed();


    // TODO: Listen for updates from background service (re-enable after notification fix)
    // FlutterBackgroundService().on('update').listen((event) {
    //   if (mounted) {
    //     setState(() {
    //       lat = event?['lat'];
    //       lon = event?['lon'];
    //       trackingStatus = (role == 'driver' && isEmergencyActive)
    //           ? "Emergency active"
    //           : "Tracking active";
    //     });
    //   }
    // });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      name = prefs.getString('name') ?? "User";
      role = prefs.getString('role') ?? "public";
      isEmergencyActive = prefs.getBool('emergency_active') ?? false;
      _userId = prefs.getString('user_id');

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
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isEmpty) {
        return;
      }

      final doc = snapshot.docs.first;
      if (doc.id == _lastAlertDocId) {
        return;
      }

      _lastAlertDocId = doc.id;
      final data = doc.data();
      final message = (data['message'] ?? FcmService.emergencyMessage).toString();

      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _lastAlertMessage = message;
          _lastAlertTime = now;
        });
      }

      await FcmService.showEmergencyLocalNotification(message: message);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_alert_doc_id', doc.id);
      await prefs.setString('last_alert_message', message);
      await prefs.setInt('last_alert_ms', now.millisecondsSinceEpoch);
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
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return;
      }

      final doc = snapshot.docs.first;
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
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() => trackingStatus = "Location denied");
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => trackingStatus = "Location permanently denied");
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

  void _startProximityScanner() {
    _proximityTimer?.cancel();
    _runAmbulanceAlertCycle();
    _proximityTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _runAmbulanceAlertCycle();
    });
  }

  Future<void> _runAmbulanceAlertCycle() async {
    try {
      await ApiService.processAmbulanceAlerts();
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
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              // TODO: Stop background service (re-enable after notification fix)
              // final service = FlutterBackgroundService();
              // service.invoke("stopService");
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
            if (_fcmToken != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Device FCM Token (Tap to copy/view):",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _fcmToken!,
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 30),
            _buildLocationCard(),
            const SizedBox(height: 40),
            if (role == 'driver') _buildDriverEmergencyPanel(),
            if (role == 'public') _buildPublicStatusPanel(),
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
          style: TextStyle(color: AppColors.darkBlue.withValues(alpha: 0.7)),
        ),
        Text(
          name,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.darkBlue,
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: role == 'driver'
                ? AppColors.primaryEmergency
                : AppColors.accentMedium,
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
              const Icon(Icons.location_on, color: AppColors.primaryEmergency),
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
        : (isEmergency ? AppColors.primaryEmergency : Colors.green);

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
            color: AppColors.darkBlue,
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
                    : AppColors.primaryEmergency,
                border: Border.all(color: AppColors.primaryEmergency, width: 8),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryEmergency.withValues(alpha: 0.3),
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
                          ? AppColors.primaryEmergency
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
                            ? AppColors.primaryEmergency
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
                  ? AppColors.primaryEmergency
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
        color: AppColors.accentLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield, color: AppColors.accentMedium),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Public mode active. Your location is being securely shared for emergency response.",
                  style: TextStyle(
                    color: AppColors.darkBlue,
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
                      color: AppColors.darkBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_lastAlertTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Received: ${_lastAlertTime!.toLocal().toString().split('.').first}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
}
