import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const RadioTribApp());
}

class RadioTribApp extends StatelessWidget {
  const RadioTribApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RadioTrib',
      theme: ThemeData.dark(),
      home: const RadioTribPage(),
    );
  }
}

class RadioTribPage extends StatefulWidget {
  const RadioTribPage({Key? key}) : super(key: key);

  @override
  State<RadioTribPage> createState() => _RadioTribPageState();
}

class _RadioTribPageState extends State<RadioTribPage> {
  late final AudioHandler _audioHandler;
  late final AudioPlayer _player;
  String _title = '';
  String _artist = '';
  String _imageUrl = '';
  bool _isLoading = true;
  double _volume = 1.0;
  Timer? _pollingTimer;

  final streamUrl = 'https://streams.radio.co/s78f983952/listen';
  final trackInfoUrl = 'https://public.radio.co/api/v2/s78f983952/track/current';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _player = AudioPlayer();
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());

    _audioHandler = await AudioService.init(
      builder: () => RadioAudioHandler(_player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.radiotrib.radiotrib.channel.audio',
        androidNotificationChannelName: 'RadioTrib Playback',
        androidNotificationOngoing: true,
      ),
    );

    await _player.setUrl(streamUrl);
    _audioHandler.play(); // ✅ Important: Start playback through AudioHandler

    _startPollingMetadata();

    setState(() {
      _isLoading = false;
    });
  }


  void _startPollingMetadata() {
    _fetchTrackInfo();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchTrackInfo());
  }

  Future<void> _fetchTrackInfo() async {
    try {
      final response = await http.get(Uri.parse(trackInfoUrl));
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final data = jsonData['data'];
        final fullTitle = data['title'] ?? '';
        final artwork = data['artwork_urls']?['large'] ?? '';

        String artist = '';
        String title = fullTitle;
        if (fullTitle.contains(' - ')) {
          final parts = fullTitle.split(' - ');
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }

        setState(() {
          _title = title;
          _artist = artist;
          _imageUrl = artwork;
        });

        _audioHandler.customAction('updateMediaItem', {
          'title': title,
          'artist': artist,
          'imageUrl': artwork,
        });
      }
    } catch (e) {
      print('Error fetching metadata: $e');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isLoading) return;
    final isPlaying = _audioHandler.playbackState.value.playing;
    if (isPlaying) {
      _audioHandler.pause();
    } else {
      _audioHandler.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/splash/fullscreen.png"),
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/background/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: StreamBuilder<PlaybackState>(
          stream: _audioHandler.playbackState,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Image.asset(
                          'assets/icon/trib.png',
                          height: 60,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(
                          _imageUrl,
                          height: 300,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.volume_down, color: Colors.white),
                        Expanded(
                          child: Slider(
                            value: _volume,
                            onChanged: (v) {
                              setState(() => _volume = v);
                              _player.setVolume(v);
                            },
                            min: 0,
                            max: 1,
                            activeColor: Colors.redAccent,
                          ),
                        ),
                        const Icon(Icons.volume_up, color: Colors.white),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _artist,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: _togglePlayPause,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(20),
                        backgroundColor: Colors.redAccent,
                      ),
                      child: Icon(
                        playing ? Icons.pause : Icons.play_arrow,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class RadioAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player;

  RadioAudioHandler(this._player) {
    // Set a default MediaItem immediately so iOS can register NowPlaying
    mediaItem.add(const MediaItem(
      id: 'radio-stream',
      album: 'RadioTrib',
      title: 'RadioTrib Live',
      artist: 'RadioTrib',
    ));

    _player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        controls: _player.playing
            ? [MediaControl.pause]
            : [MediaControl.play],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
        },
        androidCompactActionIndices: const [0],
        playing: _player.playing,
        processingState: _mapProcessingState(_player.processingState),
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
      ));
    });
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'updateMediaItem' && extras != null) {
      final title = extras['title'] as String? ?? '';
      final artist = extras['artist'] as String? ?? '';
      final imageUrl = extras['imageUrl'] as String? ?? '';

      mediaItem.add(MediaItem(
        id: 'radio-stream',
        album: 'RadioTrib',
        title: title,
        artist: artist,
        artUri: imageUrl.isNotEmpty ? Uri.parse(imageUrl) : null,
      ));
    }
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}

