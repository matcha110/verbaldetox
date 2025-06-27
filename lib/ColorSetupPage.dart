import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

class ColorSetupPage extends StatefulWidget {
  const ColorSetupPage({Key? key}) : super(key: key);

  @override
  State<ColorSetupPage> createState() => _ColorSetupPageState();
}

class _ColorSetupPageState extends State<ColorSetupPage> {
  int _currentStep = 0;
  Color _brightColor = Color(0xFFFFF1B6);
  Color _calmColor = Color(0xFFD0F5BE);
  Color _darkColor = Color(0xFFE7E7EB);
  Color _energeticColor = Color(0xFFFFC1CC);

  // カラーパレット
  final List<Color> palette = [
    Color(0xFFFFC1CC), // パステルピンク
    Color(0xFFFFF1B6), // パステルイエロー
    Color(0xFFA2E2F2), // パステルブルー
    Color(0xFFD0F5BE), // パステルグリーン
    Color(0xFFFFE5B4), // パステルオレンジ
    Color(0xFFE5D4EF), // パステルパープル
    Color(0xFFFFF6EC), // クリーム（明るいオフホワイト）
    Color(0xFFB6E2D3), // パステルミント
    Color(0xFFE7E7EB), // ライトグレー
    Color(0xFFFFD8B1), // パステルアプリコット
  ];

  String colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  // Firebase保存
  Future<void> _saveColors() async {
    // UID取得（即時反映されていない可能性があるため補完）
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // 認証状態の変化を待つ
      user = await FirebaseAuth.instance.authStateChanges().firstWhere(
            (u) => u != null,
        orElse: () => null,
      );
      if (user == null) return; // それでも取得できなければ中断
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'brightColor': colorToHex(_brightColor),
        'calmColor': colorToHex(_calmColor),
        'darkColor': colorToHex(_darkColor),
        'energeticColor': colorToHex(_energeticColor),
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('色の保存に失敗しました: $e')),
        );
      }
    }
  }


  List<Step> get _steps => [
    Step(
      title: const Text('楽しいとき'),
      content: _colorPicker(
        label: "「楽しい」ときの色を選んでください",
        color: _brightColor,
        onColor: (c) => setState(() => _brightColor = c),
      ),
      isActive: true,
    ),
    Step(
      title: const Text('落ち着くとき'),
      content: _colorPicker(
        label: "「落ち着く」ときの色を選んでください",
        color: _calmColor,
        onColor: (c) => setState(() => _calmColor = c),
      ),
      isActive: _currentStep >= 1,
    ),
    Step(
      title: const Text('悲しいとき'),
      content: _colorPicker(
        label: "「悲しい」ときの色を選んでください",
        color: _darkColor,
        onColor: (c) => setState(() => _darkColor = c),
      ),
      isActive: _currentStep >= 2,
    ),
    Step(
      title: const Text('ストレスを感じたとき'),
      content: _colorPicker(
        label: "「ストレス」を感じたときの色を選んでください",
        color: _energeticColor,
        onColor: (c) => setState(() => _energeticColor = c),
      ),
      isActive: _currentStep >= 3,
    ),
  ];

  Widget _colorPicker({required String label, required Color color, required void Function(Color) onColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          children: palette.map((c) =>
              GestureDetector(
                onTap: () => onColor(c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == c ? Colors.black : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: color == c
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
          ).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("あなたの感情の色を決めよう"),
        automaticallyImplyLeading: false,
      ),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        steps: _steps,
        onStepContinue: () async {
          if (_currentStep < 3) {
            setState(() => _currentStep += 1);
          } else {
            await _saveColors();

            // 🔽 フレーム描画後に遷移を遅延実行
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  context.go('/');
                }
              });
            }
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          }
        },
        controlsBuilder: (ctx, details) {
          return Row(
            children: [
              ElevatedButton(
                onPressed: details.onStepContinue,
                child: Text(_currentStep == 3 ? '保存してはじめる' : '次へ'),
              ),
              if (_currentStep > 0)
                TextButton(
                  onPressed: details.onStepCancel,
                  child: const Text('戻る'),
                ),
            ],
          );
        },
      ),
    );
  }
}
