import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:verbaldetox/AudioRecordPage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'utils/color_mix.dart';        // mixEmotionColors() の定義
import 'providers/user_prefs.dart';   // userPrefsProvider の定義
import 'AudioRecordPage.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';


/// 🔄 Stream を監視して GoRouter の redirect を再評価させるリスナ
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// 認証サービス
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _google = GoogleSignIn();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _google.signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(cred);
  }

  Future<UserCredential> signInWithEmail(String email, String pass) {
    return _auth.signInWithEmailAndPassword(email: email, password: pass);
  }

  Future<UserCredential> signUpWithEmail(String email, String pass) {
    return _auth.createUserWithEmailAndPassword(email: email, password: pass);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _google.signOut();
  }
}
final authProvider = Provider((ref) => AuthService());

/// ─────────────────────────────────────────────────────────────────────────────
/// ShellRoute で共通の AppBar + BottomNavigationBar を持つ
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({Key? key, required this.child}) : super(key: key);

  int _calculateSelectedIndex(String location) {
    if (location.startsWith('/input')) return 1;
    if (location.startsWith('/record')) return 2;   // ← 追加
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  void _onItemTapped(BuildContext context, int idx) {
    switch (idx) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/input');
        break;
      case 2:
        context.go('/record');    // ← 追加
        break;
      case 3:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 現在のルート情報から location を取得
    final state = GoRouterState.of(context);
    final location = state.uri.toString();
    final selected = _calculateSelectedIndex(location);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo.png'), // ロゴ画像
        ),
        title: const Text('気分屋の芝日記'),
      ),
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        currentIndex: selected,
        onTap: (idx) => _onItemTapped(context, idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home),   label: 'HOME'),
          BottomNavigationBarItem(icon: Icon(Icons.book),   label: '日記'),
          BottomNavigationBarItem(icon: Icon(Icons.mic),    label: '録音'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'プロフィール'),
        ],
      ),
    );
  }
}

/// 日付→Color を保持する StateNotifier
class HeatmapNotifier extends StateNotifier<Map<DateTime, Map<String,double>>> {
  HeatmapNotifier() : super({}) {
    _sub = _db.collection('diary').snapshots().listen((snap) {
      final m = <DateTime, Map<String,double>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final parts = (data['date'] as String).split('-');
        if (parts.length != 3) continue;
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        final x = (data['x'] as num).toDouble();
        final y = (data['y'] as num).toDouble();
        m[date] = {'x': x, 'y': y};
      }
      state = m;
    });
  }

  final _db = FirebaseFirestore.instance;
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

}


final heatmapProvider = StateNotifierProvider<
    HeatmapNotifier, Map<DateTime, Map<String,double>>>(
      (ref) => HeatmapNotifier(),
);


Future<void> main() async {
  await dotenv.load();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
// App Check を Debug プロバイダで有効化
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
  );
  runApp(const ProviderScope(child: VerbalDetoxApp()));
}

/// アプリ全体ルーティング
class VerbalDetoxApp extends ConsumerWidget {
  const VerbalDetoxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(authProvider).currentUser != null;
    final router = GoRouter(
      initialLocation: loggedIn ? '/' : '/login',
      refreshListenable: GoRouterRefreshStream(
        FirebaseAuth.instance.authStateChanges(),
      ),
      routes: [
        GoRoute(path: '/login',  builder: (_, __) => const LoginPage()),
        GoRoute(path: '/signup', builder: (_, __) => const SignupPage()),
        ShellRoute(
          builder: (ctx, state, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/',       builder: (_, __) => const HomePage()),
            GoRoute(path: '/input',  builder: (_, __) => const TextInputPage()),
            GoRoute(path: '/record', builder: (_, __) => const AudioRecordPage()),
            GoRoute(path: '/settings',builder: (_, __) => const SettingsPage()),
          ],
        ),
      ],
      redirect: (_, state) {
        final loc = state.uri.toString();
        final onAuth = loc == '/login' || loc == '/signup';
        final isLogged = FirebaseAuth.instance.currentUser != null;
        if (!isLogged && !onAuth) return '/login';
        if (isLogged && onAuth) return '/';
        return null;
      },
    );


    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'VerbalDetox',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      routerConfig: router,
    );
  }
}

/// ログイン画面
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({Key? key}) : super(key: key);
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends ConsumerState<LoginPage> {
  String _email = '', _pass = '';
  bool _loading = false;

  @override
  Widget build(BuildContext ctx) {
    final auth = ref.read(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ログイン')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(labelText: 'メールアドレス'),
            onChanged: (v) => _email = v,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'パスワード'),
            obscureText: true,
            onChanged: (v) => _pass = v,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading
                ? null
                : () async {
              setState(() => _loading = true);
              try {
                await auth.signInWithEmail(_email, _pass);
                ctx.go('/');
              } on FirebaseAuthException {
                // TODO: エラー表示
              }
              setState(() => _loading = false);
            },
            child: _loading
                ? const CircularProgressIndicator()
                : const Text('メールでログイン'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Googleでサインイン'),
            onPressed: () async {
              final res = await auth.signInWithGoogle();
              if (res != null) context.go('/');
            },
          ),
          TextButton(
            onPressed: () => context.push('/signup'),
            child: const Text('新規登録はこちら'),
          ),
        ]),
      ),
    );
  }
}

/// 新規登録画面
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({Key? key}) : super(key: key);
  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}
class _SignupPageState extends ConsumerState<SignupPage> {
  String _email = '', _pass = '';
  bool _loading = false;

  @override
  Widget build(BuildContext ctx) {
    final auth = ref.read(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('新規登録')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(labelText: 'メールアドレス'),
            onChanged: (v) => _email = v,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'パスワード'),
            obscureText: true,
            onChanged: (v) => _pass = v,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading
                ? null
                : () async {
              setState(() => _loading = true);
              try {
                await auth.signUpWithEmail(_email, _pass);
                context.go('/');
              } on FirebaseAuthException {
                // TODO: エラー表示
              }
              setState(() => _loading = false);
            },
            child: _loading
                ? const CircularProgressIndicator()
                : const Text('新規登録'),
          ),
        ]),
      ),
    );
  }
}

/// ホーム画面：月／年 のタブで切り替え
class HomePage extends ConsumerStatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _showText = false;

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(userPrefsProvider);
    return prefsAsync.when(
      data: (prefs) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('diary').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            final dataMap = <DateTime, Color>{};
            for (var doc in snap.data!.docs) {
              final d = doc.data();
              final ds = d['date'] as String?;
              if (ds == null) continue;
              final parts = ds.split('-');
              if (parts.length != 3) continue;
              final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
              final x = (d['x'] as num? ?? 0).toDouble();
              final y = (d['y'] as num? ?? 0).toDouble();
              dataMap[date] = mixEmotionColors(
                bright: prefs.bright,
                dark: prefs.dark,
                calm: prefs.calm,
                energetic: prefs.energetic,
                x: x,
                y: y,
              );
            }

            // カレンダーデータ準備
            final today = DateTime.now();
            final year = today.year;
            final month = today.month;
            final firstDay = DateTime(year, month, 1);
            final daysInMonth = DateUtils.getDaysInMonth(year, month);
            final offset = firstDay.weekday % 7;
            final totalCells = ((offset + daysInMonth) % 7 == 0)
                ? offset + daysInMonth
                : ((offset + daysInMonth) / 7).ceil() * 7;
            final cells = List<DateTime?>.generate(totalCells, (i) {
              final d = i - offset + 1;
              if (i < offset || d > daysInMonth) return null;
              return DateTime(year, month, d);
            });
            const weekLabels = ['日','月','火','水','木','金','土'];

            return DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  title: Text('$year年$month月'),
                  bottom: const TabBar(
                    tabs: [Tab(text: '月表示'), Tab(text: '年表示')],
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () async {
                        await ref.read(authProvider).signOut();
                        context.go('/login');
                      },
                    ),
                  ],
                ),
                body: TabBarView(
                  children: [
                    // 月表示
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: weekLabels
                                .map((w) => Expanded(
                              child: Center(
                                  child: Text(
                                    w,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  )),
                            ))
                                .toList(),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                childAspectRatio: 1,
                                mainAxisSpacing: 4,
                                crossAxisSpacing: 4,
                              ),
                              itemCount: cells.length,
                              itemBuilder: (ctx, idx) {
                                final date = cells[idx];
                                if (date == null) return const SizedBox();
                                final col = dataMap[date] ?? Colors.grey.shade300;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: col,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.black12),
                                  ),
                                  alignment: Alignment.topLeft,
                                  padding: const EdgeInsets.all(4),
                                  child: _showText
                                      ? Text(
                                    '${date.day}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white),
                                  )
                                      : null,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 年表示
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        children: List.generate(12, (mi) {
                          final m = mi + 1;
                          final fd = DateTime(year, m, 1);
                          final dim =
                          DateUtils.getDaysInMonth(year, m);
                          final off = fd.weekday % 7;
                          final cnt = ((off + dim) % 7 == 0)
                              ? off + dim
                              : ((off + dim) / 7).ceil()
                              * 7;
                          final monthCells =
                          List<DateTime?>.generate(cnt, (i) {
                            final d = i - off + 1;
                            if (i < off || d > dim) return null;
                            return DateTime(year, m, d);
                          });
                          return Column(
                            children: [
                              Text('$m月',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Expanded(
                                child: GridView.builder(
                                  physics:
                                  const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    childAspectRatio: 1,
                                    mainAxisSpacing: 2,
                                    crossAxisSpacing: 2,
                                  ),
                                  itemCount: monthCells.length,
                                  itemBuilder: (ctx, idx) {
                                    final date = monthCells[idx];
                                    if (date == null) return const SizedBox();
                                    final col = dataMap[date] ?? Colors.grey.shade300;
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: col,
                                        borderRadius:
                                        BorderRadius.circular(2),
                                        border: Border.all(
                                            color: Colors.black12,
                                            width: 0.5),
                                      ),
                                      alignment: Alignment.topLeft,
                                      padding: const EdgeInsets.all(2),
                                      child: _showText
                                          ? Text(
                                        '${date.day}',
                                        style: const TextStyle(
                                            fontSize: 8,
                                            color: Colors.white),
                                      )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('文字'),
                      Switch(
                        value: _showText,
                        onChanged: (v) => setState(() => _showText = v),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          body: Center(child: Text('設定読み込みエラー: \$e'))),
    );
  }
}


/// テキスト入力（感情分析）画面
class TextInputPage extends ConsumerStatefulWidget {
  const TextInputPage({Key? key}) : super(key: key);
  @override
  ConsumerState<TextInputPage> createState() => _TextInputPageState();
}

class _TextInputPageState extends ConsumerState<TextInputPage> {
  final _ctrl = TextEditingController();

  // 録音用
  final AudioRecorder _recorder = AudioRecorder();
  String? _audioPath;  // ← 録音ファイルのパスをここに保持
  bool _recording = false;

  bool _loading = false;
  Color? _resultColor;

  // ① 音声を録音 → 停止したらアップロード
  Future<void> _toggleRecord() async {
    if (_recording) {
      // stop
      await _recorder.stop();
      final path = _audioPath;
      setState(() {
        _recording = false;
        _audioPath = path;
      });
      if (path != null) await _sendAudio(path);  // ← 送信
    } else {
      // start
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.flac';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.flac,
          bitRate: 128000,
        ),
        path: filePath,
      );
      setState(() => _recording = true);
      _audioPath = filePath;
    }
  }

  // ② 音声ファイルを送信（← ここにご提示の Dio コードを挿入）
  Future<void> _sendAudio(String file) async {
    setState(() => _loading = true);
    try {
      final dio = Dio();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final form = FormData.fromMap({
        'uid': uid,
        'date': date,
        'audio': await MultipartFile.fromFile(file, filename: 'audio.flac'),
      });
      final apiUrl = dotenv.env['API_URL']!;
      final res = await dio.post('$apiUrl/diary/audio', data: form);

      final xi = (res.data['x'] as num).toDouble();
      final yi = (res.data['y'] as num).toDouble();
      final prefs = ref.read(userPrefsProvider).value!;
      final col = mixEmotionColors(
        bright: prefs.bright,
        dark: prefs.dark,
        calm: prefs.calm,
        energetic: prefs.energetic,
        x: xi,
        y: yi,
      );
      setState(() => _resultColor = col);
    } catch (e) {
      debugPrint('Audio send error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendText() async {
    if (_ctrl.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final dio = Dio();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final url = '${dotenv.env['API_URL']!}/diary';
      final res = await dio.post(
        url,
        data: FormData.fromMap({
          'uid': uid,
          'date': date,
          'text': _ctrl.text,
        }),
      );

      final xi = (res.data['x'] as num).toDouble();
      final yi = (res.data['y'] as num).toDouble();
      final prefs = ref.read(userPrefsProvider).value!;
      final col = mixEmotionColors(
        bright: prefs.bright,
        dark: prefs.dark,
        calm: prefs.calm,
        energetic: prefs.energetic,
        x: xi,
        y: yi,
      );
      setState(() {
        _resultColor = col;
        _ctrl.clear();
      });
    } catch (e) {
      debugPrint('Text send error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('テキスト送信に失敗しました')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    Future<void> _sendText() async {
      if (_ctrl.text.isEmpty) return;
      setState(() => _loading = true);
      try {
        final dio = Dio();
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
        final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final url = '${dotenv.env['API_URL']!}/diary';
        final res = await dio.post(
          url,
          data: FormData.fromMap({
            'uid': uid,
            'date': date,
            'text': _ctrl.text,
          }),
        );
        final xi = (res.data['x'] as num).toDouble();
        final yi = (res.data['y'] as num).toDouble();
        final prefs = ref.read(userPrefsProvider).value!;
        final col = mixEmotionColors(
          bright: prefs.bright,
          dark: prefs.dark,
          calm: prefs.calm,
          energetic: prefs.energetic,
          x: xi,
          y: yi,
        );
        setState(() {
          _resultColor = col;
          _ctrl.clear();
        });
      } catch (e) {
        debugPrint('Text send error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('テキスト送信に失敗しました')),
        );
      } finally {
        setState(() => _loading = false);
      }
    }

    return Scaffold(
    appBar: AppBar(title: const Text('感情分析')),
    body: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
    // -------------- テキスト入力エリア -----------------
    TextField(
    controller: _ctrl,
    maxLines: 3,
    decoration: const InputDecoration(
    border: OutlineInputBorder(),
    labelText: '今日あったこと・思ったこと',
    ),
    ),
    const SizedBox(height: 8),
    // ---------- テキスト送信ボタン ----------
    ElevatedButton(
    onPressed: _loading ? null : _sendText,
    child: _loading
    ? const CircularProgressIndicator()
        : const Text('テキスト分析'),
    ),
    const SizedBox(height: 24),
    // ---------- 音声録音ボタン ----------
    ElevatedButton.icon(
    icon: Icon(_recording ? Icons.stop : Icons.mic),
    label:
    Text(_recording ? '録音停止 & 送信' : '音声で入力（長押し可）'),
    onPressed: _loading ? null : _toggleRecord,
    ),
    const SizedBox(height: 24),
    // ---------- 結果表示 ----------
    if (_resultColor != null) ...[
      const Text('結果のカラーコード:'),
      const SizedBox(height: 8),
      Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
        color: _resultColor,
        borderRadius: BorderRadius.circular(8),
        ),
      ),
    ],
    ]),
    ),
    );
  }
}

/// 個人設定画面
class SettingsPage extends ConsumerWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final user  = FirebaseAuth.instance.currentUser!;
    final prefs = ref.watch(userPrefsProvider).value!;

    return Scaffold(
      appBar: AppBar(title: const Text('個人設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Email: ${user.email}'),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.all(16),
              child: MoodQuadrant(
                bright: prefs.bright,
                calm: prefs.calm,
                energetic: prefs.energetic,
                dark: prefs.dark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 上下の矢印＋四方向に色をつけたダイアモンド型マップ
/// 4象限グラフ版 ─────────────────────────────────────────────
// ─────────────────────────────────────────────
// グラフウィジェット
class MoodQuadrant extends StatelessWidget {
  final Color bright, calm, energetic, dark;
  const MoodQuadrant({
    Key? key,
    required this.bright,
    required this.calm,
    required this.energetic,
    required this.dark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;          // 画面幅いっぱい
        return SizedBox(
          width: size,
          height: size,                            // 1:1 を維持
          child: CustomPaint(
            painter: MoodGraphPainter(
              bright: bright,
              calm: calm,
              energetic: energetic,
              dark: dark,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Painter
class MoodGraphPainter extends CustomPainter {
  final Color bright, calm, energetic, dark;
  MoodGraphPainter({
    required this.bright,
    required this.calm,
    required this.energetic,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final halfW = w / 2, halfH = h / 2;
    final bgPaint = Paint()..style = PaintingStyle.fill;

    // 1) 背景 4 象限
    bgPaint.color = bright;    // 左上
    canvas.drawRect(Rect.fromLTWH(0, 0, halfW, halfH), bgPaint);
    bgPaint.color = energetic; // 右上
    canvas.drawRect(Rect.fromLTWH(halfW, 0, halfW, halfH), bgPaint);
    bgPaint.color = dark;      // 左下
    canvas.drawRect(Rect.fromLTWH(0, halfH, halfW, halfH), bgPaint);
    bgPaint.color = calm;      // 右下
    canvas.drawRect(Rect.fromLTWH(halfW, halfH, halfW, halfH), bgPaint);

    // 2) 十字軸＆矢印
    final axisPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 2;
    // 中央十字
    canvas.drawLine(Offset(halfW, 0), Offset(halfW, h), axisPaint);
    canvas.drawLine(Offset(0, halfH), Offset(w, halfH), axisPaint);
    // 矢印
    _drawArrow(canvas,
        from: Offset(halfW, halfH * 0.25),
        to: Offset(halfW, 8));                          // 上
    _drawArrow(canvas,
        from: Offset(halfW * 1.75, halfH),
        to: Offset(w - 8, halfH));                      // 右

    // 3) ラベル配置
    const cornerPad = 8.0;            // コーナー用余白
    const double edgePad = 4.0;      // 既存の余白
    const double vOffset = 12.0;     // 追加オフセット量
    final quadW = halfW - cornerPad * 2;
    final quadH = halfH - cornerPad * 2;

    /// 4 象限ラベル描画 ─ 左上基準
    void _drawTextCorner(String text, double x, double y, {bool right = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 11, color: Colors.black87),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: quadW);

      // 右寄せ指定なら「右端 − テキスト幅」で左上座標を決定
      final dx = right ? (x - tp.width) : x;
      tp.paint(canvas, Offset(dx, y));
    }

// ───── 4 象限ラベル ─────
    _drawTextCorner('ストレス\n緊張\n怒り',
        cornerPad,                       // ← 左上
        cornerPad);

    _drawTextCorner('わくわく\n楽しい',
        w - cornerPad,                   // ← 右上（右寄せ）
        cornerPad,
        right: true);

    _drawTextCorner('悲しみ\n退屈',
        cornerPad,                       // ← 左下
        h - cornerPad - 28);             // 行数に応じて調整

    _drawTextCorner('落ち着く\nリラックス\n癒やし',
        w - cornerPad,                   // ← 右下（右寄せ）
        h - cornerPad - 44,              // 行数に応じて調整
        right: true);

    // 中央の四辺（High/Low）
    _drawTextCenter(
      canvas,
      '覚醒\n(arousing)',
      Offset(halfW, edgePad + vOffset),
    );

    _drawTextCenter(
      canvas,
      '沈静(sleepy)',
      Offset(halfW, h - edgePad - vOffset - 14),
    );            // 下中央

    _drawTextCenter(canvas,
        '不快\n(unpleasure)',
        Offset(edgePad, halfH),
        align: TextAlign.left, anchorCenter: true);   // 左中央

    _drawTextCenter(canvas,
        '快\n(Preasure)',
        Offset(w - edgePad, halfH),
        align: TextAlign.right, anchorCenter: true);  // 右中央
  }

  /// テキスト描画（左上基準）
  void _drawText(Canvas canvas, String s, Offset pos, {required double maxW}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(fontSize: 11, color: Colors.black87),
      ),
      textDirection: ui.TextDirection.ltr,  //ui.が必要
    )..layout(maxWidth: maxW);
    tp.paint(canvas, pos);
  }

  /// テキスト描画（中心合わせ／端合わせ両対応）
  void _drawTextCenter(Canvas canvas, String s, Offset pos,
      {TextAlign align = TextAlign.center, bool anchorCenter = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(fontSize: 11, color: Colors.black87),
      ),
      textAlign: align,
      textDirection: ui.TextDirection.ltr,  //ui.が必要
    )..layout();
    final dx = anchorCenter ? pos.dx - (align == TextAlign.right ? tp.width : 0)
        : pos.dx - tp.width / 2;
    final dy = anchorCenter ? pos.dy - tp.height / 2
        : pos.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  /// 矢印ヘルパ
  void _drawArrow(Canvas canvas, {required Offset from, required Offset to}) {
    final paint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);

    const head = 6.0; // 矢印頭の長さ
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - head * cos(angle - pi / 6),
          to.dy - head * sin(angle - pi / 6))
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - head * cos(angle + pi / 6),
          to.dy - head * sin(angle + pi / 6));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}