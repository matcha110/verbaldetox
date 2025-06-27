// lib/providers/user_prefs.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/color_mix.dart';  // hexToColor が使える

final userPrefsProvider = FutureProvider<UserPrefs>((ref) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get();
  final d = snap.data() ?? {};
  return UserPrefs(
    bright:    hexToColor(d['energeticColor'] ?? '0xFFFFC1CC'), // ストレス、緊張
    calm:      hexToColor(d['calmColor'] ?? '0xFFD0F5BE'),
    dark:      hexToColor(d['darkColor'] ?? '0xFFE7E7EB'),
    energetic: hexToColor(d['brightColor'] ?? '0xFFFFF1B6'), // わくわく、楽しい
  );
});

class UserPrefs {
  const UserPrefs({
    required this.bright,
    required this.calm,
    required this.dark,
    required this.energetic,
  });
  final Color bright;
  final Color calm;
  final Color dark;
  final Color energetic;
}
