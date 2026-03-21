import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Centralized Firebase Auth + Firestore service.
/// Handles registration, email verification, login, session, and profile sync.
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Current user shortcut ─────────────────────────────────────────
  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Register with Email & Password ────────────────────────────────
  /// Creates a new Firebase Auth user and sends a verification email.
  /// Returns a result map with `success`, `message`, or `error`.
  static Future<Map<String, dynamic>> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Set display name on the auth user
      await credential.user?.updateDisplayName(name.trim());

      // Send verification email
      await credential.user?.sendEmailVerification();

      return {
        'success': true,
        'message': 'Verification link sent to your email',
        'uid': credential.user?.uid,
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _friendlyAuthError(e.code)};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ─── Resend Verification Email ─────────────────────────────────────
  static Future<Map<String, dynamic>> resendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No user is currently signed in'};
      }
      await user.sendEmailVerification();
      return {'success': true, 'message': 'Verification email resent'};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _friendlyAuthError(e.code)};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ─── Check Email Verification Status ───────────────────────────────
  /// Reloads the current user and returns whether the email is verified.
  static Future<bool> checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // ─── Save User to Firestore (after verification) ──────────────────
  /// Creates/updates the user document in the "users" collection.
  static Future<Map<String, dynamic>> saveUserToFirestore({
    required String uid,
    required String name,
    required String email,
    String? role,
  }) async {
    try {
      final docRef = _db.collection('users').doc(uid);
      final snapshot = await docRef.get();

      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {
        // FCM may not be available on all platforms
      }

      final payload = <String, dynamic>{
        'uid': uid,
        'name': name.trim(),
        'email': email.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (role != null) {
        payload['role'] = role;
      } else if (!snapshot.exists) {
        payload['role'] = 'public'; // Default for new users if not specified
      }

      if (!snapshot.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      if (fcmToken != null && fcmToken.isNotEmpty) {
        payload['fcm_token'] = fcmToken;
      }

      await docRef.set(payload, SetOptions(merge: true));

      // Persist to shared prefs for local access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', uid);
      await prefs.setString('token', uid);
      await prefs.setString('name', name.trim());
      
      // If role was provided or exists in snapshot, update prefs
      String finalRole = 'public';
      if (role != null) {
        finalRole = role;
      } else if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data['role'] != null) {
          finalRole = data['role'].toString();
        }
      }
      await prefs.setString('role', finalRole);

      return {'success': true};
    } catch (e) {
      debugPrint('saveUserToFirestore error: $e');
      return {'success': false, 'error': 'Failed to save profile: $e'};
    }
  }

  // ─── Login with Email & Password ───────────────────────────────────
  static Future<Map<String, dynamic>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        return {'success': false, 'error': 'Authentication failed'};
      }

      // Reload to get latest emailVerified status
      await user.reload();
      final refreshedUser = _auth.currentUser!;

      if (!refreshedUser.emailVerified) {
        return {
          'success': false,
          'needsVerification': true,
          'error': 'Please verify your email before logging in',
        };
      }

      // Email is verified → sync Firestore profile
      await saveUserToFirestore(
        uid: refreshedUser.uid,
        name: refreshedUser.displayName ?? 'User',
        email: refreshedUser.email ?? email,
      );

      return {
        'success': true,
        'uid': refreshedUser.uid,
        'name': refreshedUser.displayName ?? 'User',
        'email': refreshedUser.email ?? email,
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _friendlyAuthError(e.code)};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ─── Auto-login Check (session persistence) ────────────────────────
  /// Returns true if there is a signed-in, email-verified user.
  static Future<bool> isLoggedIn() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // ─── Logout ────────────────────────────────────────────────────────
  static Future<void> logout() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_id');
    await prefs.remove('role');
    await prefs.remove('name');
  }

  // ─── Friendly error messages ───────────────────────────────────────
  static String _friendlyAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in instead.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'weak-password':
        return 'The password is too weak. Use at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'invalid-credential':
        return 'Invalid email or password. Please check and try again.';
      default:
        return 'Authentication error ($code). Please try again.';
    }
  }
}
