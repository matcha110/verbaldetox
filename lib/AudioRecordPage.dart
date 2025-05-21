import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart';              // basename 用
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording(BuildContext context) async {
    // 1) マイク権限のチェック＆リクエスト
    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('マイクの使用許可が必要です')),
      );
      return;
    }

    // 2) ファイルパス作成（FLAC）
    final dir = await getTemporaryDirectory();
    final name = 'audio_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.flac';
    final path = '${dir.path}/$name';

    // 3) 録音開始（FLAC + サンプリングレート指定）
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.flac,
        bitRate: 128000,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _filePath = path;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stop(); // これで録音停止とファイル保存
    setState(() => _isRecording = false);
  }

  // Future<void> _uploadToStorage() async {
  //   if (_filePath == null) return;
  //   setState(() => _isUploading = true);
  //
  //   final user = FirebaseAuth.instance.currentUser;
  //   if (user == null) {
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(const SnackBar(content: Text('ログインしてください')));
  //     setState(() => _isUploading = false);
  //     return;
  //   }
  //
  //   final file = File(_filePath!);
  //   final ref = FirebaseStorage.instance.ref().child(
  //     'recordings/${user.uid}/${file.uri.pathSegments.last}',
  //   );
  //   try {
  //     await ref.putFile(file);
  //     final url = await ref.getDownloadURL();
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(SnackBar(content: Text('アップロード完了:\n$url')));
  //   } catch (e) {
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(SnackBar(content: Text('アップロード失敗: $e')));
  //   } finally {
  //     setState(() => _isUploading = false);
  //   }
  // }

  Future<void> _uploadToBackend(String filePath) async {
    final dio = Dio();
    final uid  = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final form = FormData.fromMap({
      'uid'       : uid,
      'date'      : date,
      'audio': await MultipartFile.fromFile(
        filePath,
        filename: basename(filePath),
        contentType: MediaType('audio', 'flac'),
      ),
    });

    final resp = await dio.post(
      '${dotenv.env['API_URL']!}/diary/audio',
      data: form,
    );

    if (resp.statusCode == 200) {
      // 成功時の処理
      final data = resp.data;
    } else {
      throw Exception('音声解析エラー: ${resp.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音声録音')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? '録音停止' : '録音開始'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : null,
              ),
              onPressed: () {
                 if (_isRecording) {
                   _stopRecording();                  // 録音停止
                 } else {
                   _startRecording(context);          // 録音開始
                 }
               },
            ),
            const SizedBox(height: 24),
            if (_filePath != null) Text('ファイル: ${_filePath!.split('/').last}'),
            const Spacer(),
            ElevatedButton.icon(
            icon: const Icon(Icons.cloud_upload),
            label: _isUploading ? Text('送信中…') : Text('送信'),
            onPressed: () {
            if (_filePath != null) {
              _uploadToBackend(_filePath!);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
