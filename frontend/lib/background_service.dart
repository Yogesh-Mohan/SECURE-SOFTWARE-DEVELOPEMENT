// import 'dart:async';
// import 'dart:ui';
// import 'package:flutter/foundation.dart';
// import 'package:flutter_background_service/flutter_background_service.dart';
// import 'package:geolocator/geolocator.dart';
// import 'api_service.dart';
// 
// Future<void> initializeBackgroundService() async {
//   final service = FlutterBackgroundService();
// 
//   await service.configure(
//     androidConfiguration: AndroidConfiguration(
//       onStart: onStart,
//       autoStart: false,
//       isForegroundMode: false,
//       notificationChannelId: 'my_foreground',
//       initialNotificationTitle: 'Location Tracking Active',
//       initialNotificationContent: 'Monitoring updates...',
//       foregroundServiceNotificationId: 888,
//     ),
//     iosConfiguration: IosConfiguration(
//       autoStart: false,
//       onForeground: onStart,
//       onBackground: onIosBackground,
//     ),
//   );
// }
// 
// @pragma('vm:entry-point')
// Future<bool> onIosBackground(ServiceInstance service) async {
//   return true;
// }
// 
// @pragma('vm:entry-point')
// void onStart(ServiceInstance service) async {
//   DartPluginRegistrant.ensureInitialized();
// 
//   Timer.periodic(const Duration(seconds: 4), (timer) async {
//     if (service is AndroidServiceInstance) {
//       if (!(await service.isForegroundService())) {
//         timer.cancel();
//       }
//     }
// 
//     try {
//       final enabled = await Geolocator.isLocationServiceEnabled();
//       if (!enabled) {
//         return;
//       }
// 
//       final permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied ||
//           permission == LocationPermission.deniedForever) {
//         return;
//       }
// 
//       // Use modern location settings
//       Position position = await Geolocator.getCurrentPosition(
//         locationSettings: AndroidSettings(
//           accuracy: LocationAccuracy.high,
//           distanceFilter: 10,
//         ),
//       );
// 
//       // Send to backend
//       bool success = await ApiService.updateLocation(
//         position.latitude,
//         position.longitude,
//       );
// 
//       if (success) {
//         service.invoke('update', {
//           "lat": position.latitude,
//           "lon": position.longitude,
//           "time": DateTime.now().toIso8601String(),
//         });
//       }
// 
//       await ApiService.processAmbulanceAlerts();
//     } catch (e) {
//       debugPrint("Error in background tracking: $e");
//     }
//   });
// }
