// lib/utils/color_mix.dart
import 'package:flutter/material.dart';

/// 16 進カラー文字列 "#RRGGBB" → Color
Color hexToColor(String hex) {
  final clean = hex.replaceFirst('#', '0xff');
  return Color(int.parse(clean));
}

Color _lerp(Color a, Color b, double t) => Color.fromARGB(
  255,
  (a.red   + (b.red   - a.red  ) * t).round(),
  (a.green + (b.green - a.green) * t).round(),
  (a.blue  + (b.blue  - a.blue ) * t).round(),
);
double _norm(double v) => (v + 10) / 20;

Color mixEmotionColors({
  required Color bright,     // (   0,1)
  required Color dark,       // (   0,0)
  required Color calm,       // (0,   0)
  required Color energetic,  // (1,   1)
  required double x,
  required double y,
}) {
  final nx = _norm(x);
  final ny = _norm(y);
  // 重みを計算
  final wNE = nx * ny;
  final wNW = (1 - nx) * ny;
  final wSW = (1 - nx) * (1 - ny);
  final wSE = nx * (1 - ny);
  // 四隅の色を取り出し
  final cNE = energetic; // 明るい＆元気
  final cNW = bright;    // 明るい＆落ち着き
  final cSW = calm;      // 暗い＆落ち着き
  final cSE = dark;      // 暗い＆元気
  // チャンネルごとに合成
  int blend(int a, int b, int c, int d, double wa, double wb, double wc, double wd) {
    return (a*wa + b*wb + c*wc + d*wd).round();
  }
  final r = blend(cNE.red, cNW.red, cSW.red, cSE.red, wNE, wNW, wSW, wSE);
  final g = blend(cNE.green, cNW.green, cSW.green, cSE.green, wNE, wNW, wSW, wSE);
  final b = blend(cNE.blue, cNW.blue, cSW.blue, cSE.blue, wNE, wNW, wSW, wSE);
  return Color.fromARGB(255, r, g, b);
}
