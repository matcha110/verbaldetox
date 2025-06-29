import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:verbaldetox/utils/color_mix.dart';
import 'package:verbaldetox/providers/user_prefs.dart';
// const String apiUrl = String.fromEnvironment('API_URL', defaultValue: '');

class AudioRecordPage extends ConsumerStatefulWidget {
  const AudioRecordPage({Key? key}) : super(key: key);

  @override
  ConsumerState<AudioRecordPage> createState() => _AudioRecordPageState();
}

class _AudioRecordPageState extends ConsumerState<AudioRecordPage> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _filePath;
  bool _isUploading = false;
  String? _transcript;
  Color? _resultColor;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording(BuildContext context) async {
    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('マイクの使用許可が必要です')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final name = 'audio_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.flac';
    final filePath = '${dir.path}/$name';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.flac, bitRate: 128000),
      path: filePath,
    );

    setState(() {
      _isRecording = true;
      _filePath = filePath;
      _transcript = null;
      _resultColor = null;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() => _isRecording = false);
  }

  Future<void> _uploadToBackend(String filePath) async {
    setState(() => _isUploading = true);

    try {
      final dio = Dio();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final form = FormData.fromMap({
        'uid': uid,
        'date': date,
        'audio': await MultipartFile.fromFile(
          filePath,
          filename: path.basename(filePath),
          contentType: MediaType('audio', 'flac'),
        ),
      });

      final resp = await dio.post('${dotenv.env['API_URL']!}/diary/audio', data: form);

      final xi = (resp.data['x'] as num).toDouble();
      final yi = (resp.data['y'] as num).toDouble();
      final transcript = resp.data['transcript'] as String? ?? '文字起こしデータがありません。';

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
        _transcript = transcript;
        _resultColor = col;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('アップロード失敗: $e')),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音声録音')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? '録音停止' : '録音開始'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : null,
                  ),
                  onPressed: () {
                    if (_isRecording) {
                      _stopRecording();
                    } else {
                      _startRecording(context);
                    }
                  },
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload),
                  label: _isUploading ? const Text('送信中…') : const Text('送信'),
                  onPressed: _filePath != null && !_isUploading
                      ? () => _uploadToBackend(_filePath!)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_filePath != null) Text('ファイル: ${path.basename(_filePath!)}'),
            if (_transcript != null) ...[
              const SizedBox(height: 24),
              Text('文字起こし結果:', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_transcript!, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              if (_resultColor != null)
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: _resultColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}