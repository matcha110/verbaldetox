// verbaldetox_sample.dart
// サインイン機能なし：Heatmap 表示 → 録音＆ダミー API 送信

// Dart のファイル・ネットワーク機能を使用
import 'dart:io';

// HTTP 通信ライブラリ（API 送信用）
import 'package:dio/dio.dart';
// Firebase を Flutter アプリに統合する初期化処理
import 'package:firebase_core/firebase_core.dart';
// Flutter の基本 UI コンポーネント
import 'package:flutter/material.dart';
// GitHub風のカラフルカレンダーウィジェット
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
// Riverpod（状態管理ライブラリ）を使用するためのパッケージ
import 'package:flutter_riverpod/flutter_riverpod.dart';
// 音声録音ライブラリ
import 'package:flutter_sound_record/flutter_sound_record.dart';
// 日付を 'yyyyMMdd' 形式に変換するためのライブラリ
import 'package:intl/intl.dart';
// 画面遷移ライブラリ（URLベースで画面を管理）
import 'package:go_router/go_router.dart';
// 録音ファイルの保存ディレクトリ取得に使う
import 'package:path_provider/path_provider.dart';

// Firebase CLI によって自動生成される設定ファイル
import 'firebase_options.dart';

// アプリ起動時のエントリーポイント
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Flutter の非同期初期化を有効に
  await Firebase.initializeApp(              // Firebase を初期化
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: VerbalDetoxApp())); // Riverpod による状態管理のルート
}

// アプリ全体のテーマやルーティングを定義するウィジェット
class VerbalDetoxApp extends ConsumerWidget {
  const VerbalDetoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // GoRouter によって画面遷移ルートを設定
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomePage()),     // ホーム画面
        GoRoute(path: '/record', builder: (_, __) => const DiaryPage()), // 録音画面
      ],
    );

    return MaterialApp.router(
      title: 'VerbalDetox',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal, // アプリ全体のテーマカラー
      ),
      routerConfig: router,
    );
  }
}

// ホーム画面：カレンダー風の感情ログを表示＋録音画面へ進むボタン
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  // 仮のダミーデータ（今日から過去30日分の感情スコアを1〜4で作る）
  Map<DateTime, int> _dummyData() {
    final now = DateTime.now();
    return {
      for (int i = 0; i < 30; i++)
        DateTime(now.year, now.month, now.day - i): (i % 4) + 1
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataSet = _dummyData();

    return Scaffold(
      appBar: AppBar(title: const Text('VerbalDetox')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/record'), // 録音画面に遷移
        child: const Icon(Icons.mic), // マイクアイコン
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: HeatMapCalendar(
            defaultColor: Colors.grey.shade300, // デフォルト色（未記録）
            flexible: true,                     // レイアウトに合わせて伸縮
            datasets: dataSet,                  // 感情データを渡す
            colorsets: const {
              1: Color(0xFF9EC5FE), // 低めの感情（例：悲しい）
              2: Color(0xFF88E0A6), // 楽しい
              3: Color(0xFFFBC252), // 嬉しい
              4: Color(0xFFF96E46), // とても嬉しい
            },
          ),
        ),
      ),
    );
  }
}

// 録音画面：ユーザーが音声で日記を話し、それをサーバーに送信する
class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> {
  final _recorder = FlutterSoundRecord(); // 録音機能のインスタンス生成
  bool _isRecording = false;              // 現在録音中かどうか
  String? _filePath;                      // 録音ファイルの保存先パス

  // 録音を開始 or 停止して送信する
  Future<void> _toggleRecord() async {
    if (!_isRecording) {
      // 録音開始時：一時フォルダにファイルを作成
      final dir = await getTemporaryDirectory();
      _filePath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(path: _filePath!, encoder: AudioEncoder.AAC);
    } else {
      // 録音停止し、ファイルを Cloud Run API に送信
      await _recorder.stop();
      if (_filePath != null) await _sendToApi(_filePath!);
    }
    // 録音状態を更新（UI を変化させる）
    setState(() => _isRecording = !_isRecording);
  }

  // 録音した音声ファイルを API に送る処理
  Future<void> _sendToApi(String path) async {
    final dio = Dio(); // HTTP 通信用オブジェクト
    final uid = 'dummy'; // 現在は仮のユーザー ID（将来は Firebase UID など）
    final date = DateFormat('yyyyMMdd').format(DateTime.now()); // 今日の日付

    // multipart/form-data 形式で送信するデータを構成
    final form = FormData.fromMap({
      'uid': uid,
      'date': date,
      'file': await MultipartFile.fromFile(path, filename: 'audio.m4a'),
    });

    try {
      // Cloud Run のエンドポイントに POST リクエスト送信
      final res = await dio.post(
        'https://example-run-xyz.a.run.app/diary',
        data: form,
      );
      debugPrint('API response: ${res.data}'); // 成功ログ
    } catch (e) {
      debugPrint('API error: $e'); // エラー発生時のログ
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('日記を録音')),
      body: Center(
        child: ElevatedButton.icon(
          onPressed: _toggleRecord, // 録音の開始または停止
          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
          label: Text(_isRecording ? '停止して送信' : '録音開始'),
        ),
      ),
    );
  }
}