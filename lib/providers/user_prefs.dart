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
    bright:    hexToColor(d['bright_color']   ?? '#FFE57F'),
    dark:      hexToColor(d['dark_color']     ?? '#004D40'),
    calm:      hexToColor(d['calm_color']     ?? '#4FC3F7'),
    energetic: hexToColor(d['energetic_color'] ?? '#FF6F00'),
  );
});

class UserPrefs {
  const UserPrefs({
    required this.bright,
    required this.dark,
    required this.calm,
    required this.energetic,
  });
  final Color bright;
  final Color dark;
  final Color calm;
  final Color energetic;
}
