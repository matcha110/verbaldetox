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
import 'firebase_options.dart';

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

/// 日付→Color を保持する StateNotifier
class HeatmapNotifier extends StateNotifier<Map<DateTime, Color>> {
  HeatmapNotifier() : super({}) {
    // Firestore の diary コレクションをリアルタイム購読
    _sub = _db.collection('diary').snapshots().listen((snap) {
      // ───── ここからデバッグ用ログ ─────
      debugPrint('🔥 Got ${snap.size} docs from /diary');
      for (final d in snap.docs) {
        debugPrint('  • ${d.id} → ${d.data()}');
      }
      // ───── ここまで ─────

      // 既存のマップ更新ロジック
      final m = <DateTime, Color>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final ds = data['date'] as String;
        final hex = data['color'] as String;
        final parts = ds.split('-');
        if (parts.length == 3) {
          final d = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
          m[d] = Color(int.parse(hex.replaceFirst('#', '0xff')));
        }
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

  Future<void> setColorForDate(DateTime date, Color color) async {
    state = {...state, date: color};
  }
}

final heatmapProvider =
    StateNotifierProvider<HeatmapNotifier, Map<DateTime, Color>>(
      (ref) => HeatmapNotifier(),
    );

Future<void> main() async {
  await dotenv.load();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: VerbalDetoxApp()));
}

/// アプリ全体ルーティング
class VerbalDetoxApp extends ConsumerWidget {
  const VerbalDetoxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final loggedIn = auth.currentUser != null;

    final router = GoRouter(
      debugLogDiagnostics: true,
      initialLocation: loggedIn ? '/' : '/login',
      refreshListenable: GoRouterRefreshStream(
        FirebaseAuth.instance.authStateChanges(),
      ),
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
        GoRoute(path: '/signup', builder: (_, __) => const SignupPage()),
        GoRoute(path: '/', builder: (_, __) => const HomePage()),
        GoRoute(path: '/input', builder: (_, __) => const TextInputPage()),
      ],
      redirect: (_, state) {
        final onAuth =
            state.matchedLocation == '/login' ||
            state.matchedLocation == '/signup';
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
        child: Column(
          children: [
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
              onPressed:
                  _loading
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
              child:
                  _loading
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
          ],
        ),
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
        child: Column(
          children: [
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
              onPressed:
                  _loading
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
              child:
                  _loading
                      ? const CircularProgressIndicator()
                      : const Text('新規登録'),
            ),
          ],
        ),
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
    final auth = ref.read(authProvider);
    final data = ref.watch(heatmapProvider); // Map<DateTime, Color>
    final today = DateTime.now();
    final year = today.year;
    final month = today.month;

    // 月初と月末
    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final startOffset = firstDayOfMonth.weekday % 7;
    final totalCount =
        ((startOffset + daysInMonth) % 7 == 0)
            ? startOffset + daysInMonth
            : ((startOffset + daysInMonth) / 7).ceil() * 7;
    final monthCells = List<DateTime?>.generate(totalCount, (i) {
      final d = i - startOffset + 1;
      if (i < startOffset || d > daysInMonth) return null;
      return DateTime(year, month, d);
    });

    // 曜日ラベル（日〜土）
    const weekLabels = ['日', '月', '火', '水', '木', '金', '土'];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${year}年${month}月'),
          bottom: const TabBar(tabs: [Tab(text: '月表示'), Tab(text: '年表示')]),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await auth.signOut();
                context.go('/login');
              },
            ),
            Row(
              children: [
                const Text('文字'),
                Switch(
                  value: _showText,
                  onChanged: (v) => setState(() => _showText = v),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/input'),
          child: const Icon(Icons.text_fields),
        ),
        body: TabBarView(
          children: [
            // ───── 月表示 ─────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 曜日ヘッダー
                  Row(
                    children:
                        weekLabels
                            .map(
                              (w) => Expanded(
                                child: Center(
                                  child: Text(
                                    w,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 8),
                  // 月カレンダー
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
                      itemCount: monthCells.length,
                      itemBuilder: (ctx, idx) {
                        final date = monthCells[idx];
                        if (date == null) return const SizedBox();
                        final col = data[date] ?? Colors.grey.shade300;
                        return Container(
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.black12),
                          ),
                          alignment: Alignment.topLeft,
                          padding: const EdgeInsets.all(4),
                          child:
                              _showText
                                  ? Text(
                                    '${date.day}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  )
                                  : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ───── 年表示 ─────
            Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: List.generate(12, (mi) {
                  final m = mi + 1;
                  // 各月のセル生成
                  final fd = DateTime(year, m, 1);
                  final dim = DateUtils.getDaysInMonth(year, m);
                  final off = fd.weekday % 7;
                  final cnt =
                      ((off + dim) % 7 == 0)
                          ? off + dim
                          : ((off + dim) / 7).ceil() * 7;
                  final cells = List<DateTime?>.generate(cnt, (i) {
                    final d = i - off + 1;
                    if (i < off || d > dim) return null;
                    return DateTime(year, m, d);
                  });
                  return Column(
                    children: [
                      Text(
                        '$m月',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                childAspectRatio: 1,
                                mainAxisSpacing: 2,
                                crossAxisSpacing: 2,
                              ),
                          itemCount: cells.length,
                          itemBuilder: (ctx, idx) {
                            final date = cells[idx];
                            if (date == null) return const SizedBox();
                            final col = data[date] ?? Colors.grey.shade300;
                            return Container(
                              decoration: BoxDecoration(
                                color: col,
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                  color: Colors.black12,
                                  width: 0.5,
                                ),
                              ),
                              alignment: Alignment.topLeft,
                              padding: const EdgeInsets.all(2),
                              child:
                                  _showText
                                      ? Text(
                                        '${date.day}',
                                        style: const TextStyle(
                                          fontSize: 8,
                                          color: Colors.white,
                                        ),
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
  String? _docId; // Firestore ドキュメント ID

  /// API へ送信して分析
  Future<void> _send() async {
    if (_ctrl.text.isEmpty) return;
    setState(() => _loading = true);

    final dio = Dio();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final url = dotenv.env['API_URL']! + '/diary';

    try {
      // ─── 1) API 呼び出し ───
      final res = await dio.post(
        url,
        data: FormData.fromMap({'uid': uid, 'date': date, 'text': _ctrl.text}),
      );

      // ─── 2) 色 & 座標を取得 ───
      final String hex = res.data['color'] as String;
      final col = Color(int.parse('0xff' + hex.substring(1)));

      setState(() {
        _resultColor = col;
        _docId = '${uid}_$date'; // StreamBuilder が購読
      });
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final defaultDocId = '${uid}_$date';

    // docId 未設定なら当日分を指す
    final docRef = FirebaseFirestore.instance
        .collection('diary')
        .doc(_docId ?? defaultDocId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('感情分析'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ─── 入力欄 ───
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
              child:
                  _loading
                      ? const CircularProgressIndicator()
                      : const Text('分析'),
            ),
            const SizedBox(height: 24),

            // ─── 色 & 座標を Firestore からリアルタイム取得 ───
            StreamBuilder(
              stream: docRef.snapshots(),
              builder: (
                context,
                AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
              ) {
                if (!snap.hasData || !snap.data!.exists) {
                  return const SizedBox.shrink();
                }

                final data = snap.data!.data()!;
                final colorHex = (data['color'] ?? '#88E0A6') as String;
                final col = Color(
                  int.parse(colorHex.substring(1), radix: 16) + 0xFF000000,
                );
                final double fun = (data['fun'] ?? 0).toDouble();
                final double bright = (data['bright'] ?? 0).toDouble();
                final double energy = (data['energy'] ?? 0).toDouble();

                return Column(
                  children: [
                    // ── 色ブロック ──
                    const Text('結果のカラーコード:'),
                    const SizedBox(height: 8),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: col,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('hex: $colorHex'),

                    const SizedBox(height: 24),

                    // ── RadarChart ──
                    SizedBox(
                      height: 260,
                      child: RadarChart(
                        RadarChartData(
                          radarShape: RadarShape.polygon,
                          tickCount: 5,
                          titlePositionPercentageOffset: 0.18,
                          titleTextStyle: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                          getTitle: (index, angle) {
                            const labels = ['楽しさ', '明るさ', '元気'];
                            return RadarChartTitle(
                              text: labels[index],
                              angle: angle,
                            );
                          },
                          dataSets: [
                            RadarDataSet(
                              dataEntries: [
                                RadarEntry(value: fun),
                                RadarEntry(value: bright),
                                RadarEntry(value: energy),
                              ],
                              fillColor: Theme.of(
                                context,
                              ).primaryColor.withOpacity(.35),
                              borderColor: Theme.of(context).primaryColor,
                              entryRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
