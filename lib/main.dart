// verbaldetox_sample.dart
// サインイン機能なし：Heatmap 表示 → テキスト入力でAPI送信し色反映
// Firestore に日付ごとのレベルを永続化
// .env から API URL を読み込む設定を追加（assets としてバンドル）

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';

/// Heatmap 用データを Firestore を介して管理する StateNotifier
class HeatmapNotifier extends StateNotifier<Map<DateTime, int>> {
  HeatmapNotifier() : super({}) {
    _loadFromFirestore();
  }

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Firestore から既存のデータを読み込む
  Future<void> _loadFromFirestore() async {
    final snapshot = await _db.collection('diary').get();
    final map = <DateTime, int>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final dateStr = data['date'] as String;
      try {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final y = int.parse(parts[0]);
          final m = int.parse(parts[1]);
          final d = int.parse(parts[2]);
          final date = DateTime(y, m, d);
          final level = data['level'] as int;
          map[DateTime(date.year, date.month, date.day)] = level;
        }
      } catch (_) {
        // フォーマット不正なエントリーは無視
      }
    }
    state = map;
  }

  /// 指定日のレベルを Firestore に保存し、ローカル state を更新
  Future<void> setLevelForDate(DateTime date, int level) async {
    final key = DateFormat('yyyy-MM-dd').format(date);
    await _db.collection('diary').doc(key).set({
      'date': key,
      'level': level,
    });
    state = {
      ...state,
      DateTime(date.year, date.month, date.day): level,
    };
  }
}

// プロバイダ定義
final heatmapProvider = StateNotifierProvider<HeatmapNotifier, Map<DateTime, int>>(
      (ref) => HeatmapNotifier(),
);

Future<void> main() async {
  // .env は pubspec.yaml の assets: に登録
  await dotenv.load();

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: VerbalDetoxApp()));
}

class VerbalDetoxApp extends ConsumerWidget {
  const VerbalDetoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomePage()),
        GoRoute(path: '/input', builder: (_, __) => const TextInputPage()),
      ],
    );
    return MaterialApp.router(
      title: 'VerbalDetox',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      routerConfig: router,
    );
  }
}

/// ホーム画面（Heatmap 表示）
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataSet = ref.watch(heatmapProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('VerbalDetox')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/input'),
        child: const Icon(Icons.text_fields),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: HeatMapCalendar(
            defaultColor: Colors.grey.shade300,
            flexible: true,
            datasets: dataSet,
            colorMode: ColorMode.color, // 追加: レベルごとに色を使い分け
            colorsets: const {
              1: Color(0xFF9EC5FE), // Level 1
              2: Color(0xFF88E0A6), // Level 2
              3: Color(0xFFFBC252), // Level 3
              4: Color(0xFFF96E46), // Level 4
            },
          ),
        ),
      ),
    );
  }
}

/// テキスト入力画面
class TextInputPage extends ConsumerStatefulWidget {
  const TextInputPage({super.key});
  @override
  ConsumerState<TextInputPage> createState() => _TextInputPageState();
}

class _TextInputPageState extends ConsumerState<TextInputPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  Color? _resultColor;

  Future<void> _sendText() async {
    if (_controller.text.isEmpty) return;
    setState(() => _loading = true);
    final dio = Dio();
    final uid = 'dummy';
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final baseUrl = dotenv.env['API_URL'] ?? '';
    final endpoint = '$baseUrl/diary';

    try {
      final form = FormData.fromMap({
        'uid': uid,
        'date': date,
        'text': _controller.text,
      });
      final res = await dio.post(endpoint, data: form);
      debugPrint('API raw data: ${res.data}');
      final level = res.data['level'] as int;
      final colorHex = res.data['color'] as String;
      await ref.read(heatmapProvider.notifier).setLevelForDate(DateTime.now(), level);
      setState(() => _resultColor = Color(int.parse(colorHex.replaceFirst('#', '0xff'))));
    } catch (e) {
      debugPrint('API error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('テキスト感情分析'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '今日あったこと・思ったこと',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _sendText,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('感情を分析して色を取得'),
            ),
            const SizedBox(height: 24),
            if (_resultColor != null) ...[
              const Text('分析結果の色:'),
              const SizedBox(height: 8),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _resultColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// pubspec.yaml に追加：
// dependencies:
//   flutter_dotenv: ^5.0.2
//   cloud_firestore: ^5.6.6
// flutter:
//   assets:
//     - .env