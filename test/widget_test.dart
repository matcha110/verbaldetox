// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbaldetox/main.dart'; // VerbalDetoxApp をインポート

void main() {
  testWidgets('App のスモークテスト', (WidgetTester tester) async {
    // MyApp() ではなく、ProviderScope でラップした VerbalDetoxApp を起動
    await tester.pumpWidget(
      const ProviderScope(
        child: VerbalDetoxApp(),
      ),
    );

    // 例えばログイン画面の AppBar タイトルが出ているかを確認
    expect(find.text('ログイン'), findsOneWidget);
  });
}
