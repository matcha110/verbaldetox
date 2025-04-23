import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

/// 🔄 Stream を監視して ChangeNotifier として使うだけのシンプルな実装
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

  /// Google サインイン
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

  /// Email/Password ログイン
  Future<UserCredential> signInWithEmail(String email, String pass) {
    return _auth.signInWithEmailAndPassword(email: email, password: pass);
  }

  /// Email/Password 新規登録
  Future<UserCredential> signUpWithEmail(String email, String pass) {
    return _auth.createUserWithEmailAndPassword(email: email, password: pass);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _google.signOut();
  }
}
final authProvider = Provider((ref) => AuthService());

/// Firestore と同期させる Heatmap 用 StateNotifier
class HeatmapNotifier extends StateNotifier<Map<DateTime,int>> {
  HeatmapNotifier(): super({}) {
    _load();
  }
  final _db = FirebaseFirestore.instance;

  Future<void> _load() async {
    final snap = await _db.collection('diary').get();
    final m = <DateTime,int>{};
    for (var doc in snap.docs) {
      final data = doc.data();
      final ds = data['date'] as String; // "yyyy-MM-dd"
      final lvl = data['level'] as int;
      final parts = ds.split('-');
      if (parts.length == 3) {
        final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        m[d] = lvl;
      }
    }
    state = m;
  }

  Future<void> setLevelForDate(DateTime date, int level) async {
    final key = DateFormat('yyyy-MM-dd').format(date);
    await _db.collection('diary').doc(key).set({
      'date': key,
      'level': level,
    });
    state = {...state, date: level};
  }
}
final heatmapProvider = StateNotifierProvider<HeatmapNotifier, Map<DateTime,int>>(
      (ref) => HeatmapNotifier(),
);

Future<void> main() async {
  await dotenv.load();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: VerbalDetoxApp()));
}

/// アプリ全体
class VerbalDetoxApp extends ConsumerWidget {
  const VerbalDetoxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final loggedIn = auth.currentUser != null;

    final router = GoRouter(
      debugLogDiagnostics: true,
      refreshListenable: GoRouterRefreshStream(
        FirebaseAuth.instance.authStateChanges(),
      ),
      routes: [
        GoRoute(path: '/login',  builder: (_, __) => const LoginPage()),
        GoRoute(path: '/signup', builder: (_, __) => const SignupPage()),
        GoRoute(path: '/',       builder: (_, __) => const HomePage()),
        GoRoute(path: '/input',  builder: (_, __) => const TextInputPage()),
      ],
      redirect: (BuildContext ctx, GoRouterState state) {
        // state.matchedLocation で「現在マッチしているルートのパス」を取得
        final isOnAuthPage = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
        final isLoggedIn  = FirebaseAuth.instance.currentUser != null;

        // ログインしていないのに /login でも /signup でもないなら /login へ飛ばす
        if (!isLoggedIn && !isOnAuthPage) return '/login';
        // ログイン済みなのに /login or /signup にいるならホームへ
        if (isLoggedIn  &&  isOnAuthPage) return '/';

        return null; // それ以外は何もしない
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
            onPressed: _loading ? null : () async {
              setState(() => _loading = true);
              try {
                await auth.signInWithEmail(_email, _pass);
                context.go('/');
              } on FirebaseAuthException catch (e) {
                // エラー処理（省略可能）
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
            onPressed: _loading ? null : () async {
              setState(() => _loading = true);
              try {
                await auth.signUpWithEmail(_email, _pass);
                context.go('/');
              } on FirebaseAuthException catch (e) {
                // エラー処理
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

/// ホーム画面
class HomePage extends ConsumerWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authProvider);
    final data = ref.watch(heatmapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('VerbalDetox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.signOut();
              context.go('/login');
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/input'),
        child: const Icon(Icons.text_fields),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: HeatMapCalendar(
          defaultColor: Colors.grey.shade300,
          flexible: true,
          datasets: data,
          colorMode: ColorMode.color,
          colorsets: const {
            1: Color(0xFF9EC5FE),
            2: Color(0xFF88E0A6),
            3: Color(0xFFFBC252),
            4: Color(0xFFF96E46),
          },
        ),
      ),
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
  bool _loading = false;
  Color? _resultColor;

  Future<void> _send() async {
    if (_ctrl.text.isEmpty) return;
    setState(() => _loading = true);

    final dio = Dio();
    final uid  = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final url  = dotenv.env['API_URL']! + '/diary';

    try {
      final res = await dio.post(url, data: FormData.fromMap({
        'uid': uid,
        'date': date,
        'text': _ctrl.text,
      }));
      final lvl = res.data['level'] as int;
      final hex = res.data['color'] as String;
      await ref.read(heatmapProvider.notifier)
          .setLevelForDate(DateTime.now(), lvl);
      setState(() {
        _resultColor = Color(int.parse(hex.replaceFirst('#','0xff')));
      });
    } catch (_) {
      // error
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('感情分析'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '今日あったこと・思ったこと',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _send,
            child: _loading
                ? const CircularProgressIndicator()
                : const Text('分析'),
          ),
          const SizedBox(height: 24),
          if (_resultColor != null) ...[
            const Text('結果の色:'),
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
        ]),
      ),
    );
  }
}
