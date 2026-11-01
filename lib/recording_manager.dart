import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_session.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 单个录制任务
class RecordingTask {
  final String id;
  final String title;
  final String url;
  File? file;
  FFmpegSession? session;
  bool isRecording = false;
  bool isFinished = false;
  int seconds = 0;
  Timer? _timer;

  RecordingTask(this.id, this.title, this.url);

  String get filePath => file?.path ?? '';
}

/// 全局录制管理器，管理多个录制任务
class RecordingManager {
  RecordingManager._();
  static final RecordingManager instance = RecordingManager._();

  final List<RecordingTask> tasks = [];
  int _seq = 0;

  /// 启动一个录制任务
  Future<RecordingTask?> start(String title, String url) async {
    try {
      final id = 'rec${_seq++}_${DateTime.now().millisecondsSinceEpoch}';
      final task = RecordingTask(id, title, url);
      final dir = await getApplicationDocumentsDirectory();
      final name = 'record_${DateTime.now().millisecondsSinceEpoch}.mkv';
      task.file = File('${dir.path}/$name');
      task.isRecording = true;

      // 计时器先创建，任务结束时能正常取消
      task._timer = Timer.periodic(const Duration(seconds: 1), (_) {
        task.seconds++;
      });

      task.session = await FFmpegKit.executeAsync(
        '-reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 '
        '-rw_timeout 5000000 -i "${url}" -c copy -f matroska -y "${task.file!.path}"',
        (session) {
          // 任务结束（正常完成、出错或被取消）
          task.isRecording = false;
          task.isFinished = true;
          task._timer?.cancel();
        },
      );

      tasks.add(task);
      return task;
    } catch (_) {
      return null;
    }
  }

  /// 停止指定任务
  Future<void> stop(RecordingTask task) async {
    if (task.session != null) {
      await FFmpegKit.cancel(task.session!.getSessionId());
    }
    task.session = null;
    task.isRecording = false;
    task._timer?.cancel();
  }

  /// 该链接当前是否有任务在录
  bool isRecording(String url) {
    return tasks.any((t) => t.url == url && t.isRecording);
  }

  /// 该链接当前正在录的任务
  RecordingTask? activeTaskOf(String url) {
    for (final t in tasks) {
      if (t.url == url && t.isRecording) return t;
    }
    return null;
  }

  /// 切换录制：该链接在录就停止，没在录就启动
  Future<bool> toggle(String title, String url) async {
    final active = activeTaskOf(url);
    if (active != null) {
      await stop(active);
      return false;
    }
    final task = await start(title, url);
    return task != null;
  }
}

String _fmtTime(int s) {
  final h = (s ~/ 3600).toString().padLeft(2, '0');
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return h == '00' ? '$m:$sec' : '$h:$m:$sec';
}

/// 录制进度界面：列出所有录制任务
class RecordingListScreen extends StatefulWidget {
  const RecordingListScreen({super.key});

  @override
  State<RecordingListScreen> createState() => _RecordingListScreenState();
}

class _RecordingListScreenState extends State<RecordingListScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = RecordingManager.instance.tasks;
    return Scaffold(
      appBar: AppBar(
        title: const Text('录制任务'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: tasks.isEmpty
          ? const Center(child: Text('暂无录制任务'))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final t = tasks[index];
                final status = t.isRecording ? '录制中' : (t.isFinished ? '已结束' : '已停止');
                return ListTile(
                  leading: Icon(
                    t.isRecording ? Icons.fiber_manual_record : Icons.videocam_off,
                    color: t.isRecording ? Colors.red : Colors.grey,
                  ),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '$status · ${_fmtTime(t.seconds)}'
                    '${t.filePath.isNotEmpty ? '\n${t.filePath}' : ''}',
                  ),
                  trailing: t.isRecording
                      ? IconButton(
                          icon: const Icon(Icons.stop, color: Colors.red),
                          onPressed: () => RecordingManager.instance.stop(t),
                        )
                      : const Icon(Icons.check_circle, color: Colors.grey),
                );
              },
            ),
    );
  }
}
