# VerbalDetox

音声から感情を分析し、ユーザーの気分を視覚的に記録するメンタルヘルスサポートアプリです。Firebase、Riverpod、DioなどのモダンなFlutterパッケージを活用し、Googleサインインや録音・文字走り・感情分析のAPI連携を実現しています。

---

## 🛠 機能概要

### 🎙 音声入力による感情分析

* ユーザーは、日々の感情を音声（録音）で入力
* 録音した音声は `.flac` 形式で保存し、API に送信
* APIは、入力から感情の座標 `(x, y)` を返し、独自の色で視覚化

### 🌈 ヒートマップによるカレンダー表示

* 月表示・年表示の2タブ切り替え
* 感情の変化をカラーコードでカレンダーにマッピング
* 感情の色情報はユーザー設定から取得し、個別に調整可能

### 👤 Firebase 認証と Firestore 連携

* Google アカウントまたはメールアドレスによるサインイン
* Firestore に日毎の感情データを保存・リアルタイム反映

### ⚙ 感情パレットのカスタマイズ

* 明るい・暗い・落ち着き・元気の4象限を色で定義
* `SettingsPage` で自分好みの感情表現にカスタマイズ

---

## 📦 使用パッケージ

| パッケージ名               | 用途                     |
| -------------------- | ---------------------- |
| `firebase_core`      | Firebase 初期化           |
| `firebase_auth`      | Google サインイン、メールログイン対応 |
| `cloud_firestore`    | 感情データの保存・取得            |
| `flutter_riverpod`   | 状態管理（Provider）         |
| `go_router`          | ルーティング                 |
| `flutter_dotenv`     | API URLの環境変数管理         |
| `record`             | 音声録音機能                 |
| `dio`                | バックエンド API との通信        |
| `path_provider`      | 一時ファイル保存場所の取得          |
| `intl`               | 日付フォーマット               |
| `firebase_app_check` | アプリ検証（debugプロバイダを使用）   |
| `fl_chart`           | 感情カラーマップ用グラフ描画（設定画面）   |

---

## 🚀 セットアップ手順

1. **Firebase プロジェクトの作成**

    * Authenticationにて Google 、Email/Password を有効化
    * Firestore を有効化

2. **`.env` ファイルを作成**

   ```env
   API_URL=https://your-cloud-run-endpoint
   ```

3. **Firebase 初期設定**

   ```bash
   flutterfire configure
   ```

4. **依存パッケージのインストール**

   ```bash
   flutter pub get
   ```

5. **アプリ起動**

   ```bash
   flutter run
   ```

---

## 📁 ディレクトリ構成（抜粋）

```
lib/
├── main.dart
├── AudioRecordPage.dart
├── ColorSetupPage.dart
├── providers/
│   └── user_prefs.dart
├── utils/
│   └── color_mix.dart
```

---

## 🔄 感情の色の混合ロジック

感情の座標 `(x, y)` を4象限にマッピングし、以下のカラーバランスで補間：

```
          ↑ arousing
          |
  bright  |  energetic
  --------+--------→ pleasure
   dark   |   calm
          |
        sleepy
```

`mixEmotionColors()` 関数を用いて、4色を重みづけ合成。

---

## 📄 バックエンド API の期待する仕様

### `/diary/audio` (POST)

* `uid`: ユーザーID
* `date`: `YYYY-MM-DD`
* `audio`: `.flac`形式ファイル

**レスポンス例**:

```json
{
  "x": 6,
  "y": -2,
  "transcript": "今日はとても楽しかったです"
}
```
