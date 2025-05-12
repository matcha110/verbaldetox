import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('マイクの権限がありません')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final name =
        'audio_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.m4a';
    final path = '${dir.path}/$name';

    // RecordConfig を渡す
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
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

  Future<void> _uploadToStorage() async {
    if (_filePath == null) return;
    setState(() => _isUploading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ログインしてください')));
      setState(() => _isUploading = false);
      return;
    }

    final file = File(_filePath!);
    final ref = FirebaseStorage.instance.ref().child(
      'recordings/${user.uid}/${file.uri.pathSegments.last}',
    );
    try {
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('アップロード完了:\n$url')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('アップロード失敗: $e')));
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
          children: [
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? '録音停止' : '録音開始'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : null,
              ),
              onPressed: _isRecording ? _stopRecording : _startRecording,
            ),
            const SizedBox(height: 24),
            if (_filePath != null) Text('ファイル: ${_filePath!.split('/').last}'),
            const Spacer(),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label:
                  _isUploading ? const Text('アップロード中…') : const Text('アップロード'),
              onPressed: _isUploading ? null : _uploadToStorage,
            ),
          ],
        ),
      ),
    );
  }
}
