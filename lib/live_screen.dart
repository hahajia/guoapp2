import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_session.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// 直播整合功能 v2

class LivePlatform {
  final String address;
  final String title;
  final String img;
  final int count;

  LivePlatform({
    required this.address,
    required this.title,
    required this.img,
    required this.count,
  });

  factory LivePlatform.fromJson(Map<String, dynamic> json) {
    return LivePlatform(
      address: json['address'] ?? '',
      title: json['title'] ?? '',
      img: json['xinimg'] ?? '',
      count: int.tryParse(json['Number']?.toString() ?? '0') ?? 0,
    );
  }
}

class LiveChannel {
  final String name;
  final String url;
  final String img;
  final String platform;

  LiveChannel({
    required this.name,
    required this.url,
    required this.img,
    required this.platform,
  });

  factory LiveChannel.fromJson(Map<String, dynamic> json, String platform) {
    return LiveChannel(
      name: json['title'] ?? '',
      url: json['address'] ?? '',
      img: json['img'] ?? '',
      platform: platform,
    );
  }
}

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  static const String _baseUrl = 'http://api.hclyz.com:81/mf/';

  List<LivePlatform> _platforms = [];
  List<LiveChannel> _allChannels = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final platformList = await _fetchPlatforms();
      if (!mounted) return;
      setState(() => _platforms = platformList);

      final results = await Future.wait(
        platformList.map((p) => _fetchChannels(p)),
      );

      final all = <LiveChannel>[];
      for (final channels in results) {
        all.addAll(channels);
      }

      final unique = _deduplicateByUrl(all);

      if (!mounted) return;
      setState(() {
        _allChannels = unique;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  Future<List<LivePlatform>> _fetchPlatforms() async {
    final res = await http.get(Uri.parse('$_baseUrl/json.txt'));
    if (res.statusCode != 200) throw Exception('平台列表请求失败');

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['pingtai'] as List<dynamic>? ?? [];

    return list
        .map((e) => LivePlatform.fromJson(e as Map<String, dynamic>))
        // 过滤掉指定的平台
        .where((p) => p.title != '卫视直播' && !p.title.startsWith('欧美'))
        .toList();
  }

  Future<List<LiveChannel>> _fetchChannels(LivePlatform platform) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/${platform.address}'));
      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['zhubo'] as List<dynamic>? ?? [];

      return list
          .map((e) => LiveChannel.fromJson(e as Map<String, dynamic>, platform.title))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<LiveChannel> _deduplicateByUrl(List<LiveChannel> channels) {
    final seen = <String>{};
    final result = <LiveChannel>[];

    for (final c in channels) {
      final key = _normalizeUrl(c.url);
      if (key.isEmpty) {
        // 无有效链接的频道不参与去重，直接保留
        result.add(c);
        continue;
      }

      if (seen.add(key)) {
        result.add(c);
      }
    }

    return result;
  }

  String _normalizeUrl(String url) {
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      return '${uri.host}${uri.path}'.toLowerCase();
    } catch (_) {
      return url.toLowerCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('整合频道'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadAll,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAll,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final filtered = _filter.isEmpty
        ? _allChannels
        : _allChannels
            .where((c) => c.name.toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜索频道...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('整合频道：${filtered.length} 个'),
              const SizedBox(width: 8),
              Text('（已去重，原始共 ${_allChannels.length} 个）',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final channel = filtered[index];
              return _buildChannelCard(channel);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChannelCard(LiveChannel channel) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LivePlayerScreen(
              url: channel.url,
              title: channel.name,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 实时预览 - 小播放器
            Expanded(
              child: _LivePreview(url: channel.url),
            ),
            // 文字信息
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    channel.platform,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 简单的直播播放页面
class LivePlayerScreen extends StatefulWidget {
  final String url;
  final String title;

  const LivePlayerScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen> {
  late Player _player;
  late VideoController _controller;
  bool _initialized = false;
  String? _error;
  bool _recording = false;
  File? _recordFile;
  Timer? _recordTimer;
  int _recordSeconds = 0;
  FFmpegSession? _recordSession;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _player = Player();
      _controller = VideoController(_player);
      await _player.open(Media(widget.url));
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '播放失败: $e');
      }
    }
  }

  /// 开始或停止录制
  Future<void> _toggleRecord() async {
    if (_recording) {
      // 停止录制
      final sessionId = _recordSession?.getSessionId();
      if (sessionId != null) {
        await FFmpegKit.cancel(sessionId);
      }
      _recordSession = null;
      _recordTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordSeconds = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('录制已保存: ${_recordFile?.path ?? ''}')),
      );
    } else {
      // 开始录制
      try {
        final dir = await getApplicationDocumentsDirectory();
        final name = 'record_${DateTime.now().millisecondsSinceEpoch}.mkv';
        _recordFile = File('${dir.path}/$name');
        _recordSession = await FFmpegKit.executeAsync(
          '-i "${widget.url}" -c copy -f matroska -y "${_recordFile!.path}"',
          (session) {},
        );
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _recordSeconds++);
          }
        });
        if (!mounted) return;
        setState(() => _recording = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('录制失败: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmtTime(int s) {
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return h == '00' ? '$m:$sec' : '$h:$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_initialized)
            IconButton(
              icon: _recording
                  ? const Icon(Icons.stop, color: Colors.red, size: 32)
                  : const Icon(Icons.fiber_manual_record,
                      color: Colors.red, size: 28),
              tooltip: _recording ? '停止录制' : '开始录制',
              onPressed: _toggleRecord,
            ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _initialized = false;
                      });
                      _initPlayer();
                    },
                    child: const Text('重试'),
                  ),
                ],
              )
            : !_initialized
                ? const CircularProgressIndicator()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(controller: _controller),
                      // 录制指示器
                      if (_recording)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'REC ${_fmtTime(_recordSeconds)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

/// 全局预览加载队列，一个一个加载
class _PreviewQueue {
  static final _PreviewQueue _instance = _PreviewQueue._internal();
  factory _PreviewQueue() => _instance;
  _PreviewQueue._internal();

  final List<void Function()> _queue = [];
  bool _isLoading = false;
  final Set<String> _loaded = {};

  bool isLoaded(String url) => _loaded.contains(url);

  void add(String url, void Function() onReady) {
    if (_loaded.contains(url)) {
      onReady();
      return;
    }
    _queue.add(onReady);
    _processNext();
  }

  Future<void> _processNext() async {
    if (_isLoading || _queue.isEmpty) return;
    _isLoading = true;
    final task = _queue.removeAt(0);
    await Future.delayed(const Duration(milliseconds: 500)); // 间隔 0.5 秒
    task();
    _isLoading = false;
    _processNext();
  }
}

/// 小的实时预览播放器
class _LivePreview extends StatefulWidget {
  final String url;

  const _LivePreview({required this.url});

  @override
  State<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<_LivePreview> {
  Player? _player;
  VideoController? _controller;
  bool _initialized = false;
  final _queue = _PreviewQueue();

  @override
  void initState() {
    super.initState();
    _queue.add(widget.url, _initPlayer);
  }

  Future<void> _initPlayer() async {
    if (!mounted) return;
    try {
      _player = Player();
      _controller = VideoController(_player!);
      await _player!.open(Media(widget.url));
      await _player!.setVolume(0); // 静音
      // 等 1 秒让第一帧出来，然后暂停
      await Future.delayed(const Duration(seconds: 1));
      await _player!.pause();
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (_) {
      // 加载失败就显示默认图标
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _controller == null) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.live_tv, size: 48, color: Colors.grey),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Video(controller: _controller!),
        // 直播中标签
        Positioned(
          top: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '直播中',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}