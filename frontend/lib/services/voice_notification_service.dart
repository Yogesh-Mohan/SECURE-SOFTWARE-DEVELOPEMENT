import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

/// Service to handle text-to-speech voice notifications for emergency alerts.
/// Uses native Android TTS engine for free, offline speech synthesis.
class VoiceNotificationService {
  static final VoiceNotificationService _instance =
      VoiceNotificationService._internal();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  VoiceNotificationService._internal();

  factory VoiceNotificationService() {
    return _instance;
  }

  /// Initialize the TTS engine (call this on app startup)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set default language to device system language
      await _flutterTts.setLanguage('en-US');

      // Set speech rate (0.5 = slower, 1.0 = normal, 2.0 = faster)
      await _flutterTts.setSpeechRate(0.5);

      // Set pitch (1.0 = normal, lower = deeper voice, higher = higher voice)
      await _flutterTts.setPitch(1.0);

      // Set volume (0.0 to 1.0, this respects system volume settings)
      await _flutterTts.setVolume(1.0);

      _isInitialized = true;
      debugPrint('VoiceNotificationService: TTS initialized successfully');
    } catch (e) {
      debugPrint('VoiceNotificationService: Failed to initialize TTS - $e');
    }
  }

  /// Speak an alert message using text-to-speech
  /// Message is cleaned of emojis and special characters for clear pronunciation
  Future<void> speakAlert(String message) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Clean up message for voice: remove emojis, extra whitespace
      final cleanedMessage = _cleanMessageForVoice(message);

      debugPrint(
          'VoiceNotificationService: Speaking alert - "$cleanedMessage"');

      // Speak the message
      await _flutterTts.speak(cleanedMessage);
    } catch (e) {
      debugPrint('VoiceNotificationService: Failed to speak alert - $e');
    }
  }

  /// Stop any ongoing speech
  Future<void> stopSpeaking() async {
    try {
      await _flutterTts.stop();
      debugPrint('VoiceNotificationService: Stopped speaking');
    } catch (e) {
      debugPrint('VoiceNotificationService: Failed to stop speaking - $e');
    }
  }

  /// Set the TTS language code (e.g., 'en-US', 'es-ES', 'hi-IN')
  Future<void> setLanguage(String languageCode) async {
    try {
      await _flutterTts.setLanguage(languageCode);
      debugPrint('VoiceNotificationService: Language set to $languageCode');
    } catch (e) {
      debugPrint('VoiceNotificationService: Failed to set language - $e');
    }
  }

  /// Set speech rate (0.5 = slow, 1.0 = normal, 2.0 = fast)
  Future<void> setSpeechRate(double rate) async {
    try {
      await _flutterTts.setSpeechRate(rate);
      debugPrint('VoiceNotificationService: Speech rate set to $rate');
    } catch (e) {
      debugPrint('VoiceNotificationService: Failed to set speech rate - $e');
    }
  }

  /// Set volume level (0.0 to 1.0, respects system volume)
  Future<void> setVolume(double volume) async {
    try {
      final clampedVolume = volume.clamp(0.0, 1.0);
      await _flutterTts.setVolume(clampedVolume);
      debugPrint('VoiceNotificationService: Volume set to $clampedVolume');
    } catch (e) {
      debugPrint('VoiceNotificationService: Failed to set volume - $e');
    }
  }



  /// Dispose of TTS resources
  Future<void> dispose() async {
    try {
      await _flutterTts.stop();
      _isInitialized = false;
      debugPrint('VoiceNotificationService: Disposed');
    } catch (e) {
      debugPrint('VoiceNotificationService: Error during disposal - $e');
    }
  }

  /// Clean message for voice notification:
  /// - Remove emojis and special characters
  /// - Clean up extra whitespace
  /// - Simplify punctuation
  String _cleanMessageForVoice(String message) {
    // Remove emoji and special characters, keep only alphanumeric and basic punctuation
    String cleaned =
        message.replaceAll(RegExp(r"[^\w\s.,!?'\-]"), '').trim();

    // Replace multiple spaces with single space
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    // Remove extra punctuation for clearer speech
    cleaned = cleaned.replaceAll('...', '.');
    cleaned = cleaned.replaceAll('!!', '!');

    return cleaned.isNotEmpty ? cleaned : 'Alert received';
  }

  /// Check if TTS is initialized
  bool get isInitialized => _isInitialized;
}
