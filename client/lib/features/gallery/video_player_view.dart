import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/models/gallery_media_item.dart';

class VideoPlayerView extends StatefulWidget {
  final GalleryMediaItem item;
  final String serverBaseUrl;
  final bool isCurrentPage;

  const VideoPlayerView({
    super.key,
    required this.item,
    required this.serverBaseUrl,
    this.isCurrentPage = true,
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  bool _isMuted = false;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrentPage != widget.isCurrentPage) {
      if (!widget.isCurrentPage && _controller != null && _controller!.value.isPlaying) {
        _controller!.pause();
      }
    }
  }

  Future<void> _initVideo() async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      if (widget.item.isLocal && widget.item.localEntity != null) {
        final File? file = await widget.item.localEntity!.originFile ?? await widget.item.localEntity!.file;
        if (file == null || !await file.exists()) {
          throw Exception('File video lokal tidak dapat diakses dari galeri sistem.');
        }
        _controller = VideoPlayerController.file(file);
      } else if (widget.item.isServer && widget.item.serverItem != null) {
        // 1. If this video is also stored on this iPhone, play local file directly for zero-latency instant playback!
        if (widget.item.localEntity != null) {
          try {
            final File? localFile = await widget.item.localEntity!.originFile ?? await widget.item.localEntity!.file;
            if (localFile != null && await localFile.exists()) {
              _controller = VideoPlayerController.file(localFile);
            }
          } catch (_) {}
        }

        // 2. Otherwise, stream from server with native AVPlayer Range handling
        if (_controller == null) {
          final String rawUrl = widget.item.serverItem!.rawUrl(widget.serverBaseUrl);
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(rawUrl),
          );
        }
      } else {
        throw Exception('Sumber video tidak valid.');
      }

      try {
        await _controller!.initialize();
      } catch (initErr) {
        // Fallback to base raw url if video extension url failed
        if (widget.item.isServer && widget.item.serverItem != null) {
          final fallbackUrl = '${widget.serverBaseUrl}/media/${widget.item.id}/raw';
          try {
            await _controller?.dispose();
            _controller = VideoPlayerController.networkUrl(Uri.parse(fallbackUrl));
            await _controller!.initialize();
          } catch (fallbackErr) {
            throw Exception(
              'Gagal memuat video dari server (${widget.serverBaseUrl}): $initErr\n'
              'Pastikan Sam Connected Server di PC sudah diperbarui dan aktif di jaringan Wi-Fi.',
            );
          }
        } else {
          rethrow;
        }
      }
      _controller!.setLooping(false);
      _controller!.addListener(_onControllerUpdate);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        if (widget.isCurrentPage) {
          _startHideTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _showControlsTemporarily(stayVisible: true);
    } else {
      if (_controller!.value.position >= _controller!.value.duration) {
        _controller!.seekTo(Duration.zero);
      }
      _controller!.play();
      _startHideTimer();
    }
  }

  void _toggleMute() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _showControlsTemporarily({bool stayVisible = false}) {
    setState(() {
      _showControls = true;
    });
    if (!stayVisible) {
      _startHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.orangeAccent),
              const SizedBox(height: 12),
              const Text(
                'Tidak Dapat Memutar Video',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _initVideo,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }

    final value = _controller!.value;
    final isPlaying = value.isPlaying;
    final isFinished = value.position >= value.duration;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_showControls) {
          setState(() {
            _showControls = false;
          });
          _hideControlsTimer?.cancel();
        } else {
          _showControlsTemporarily();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video Surface
          Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
              child: VideoPlayer(_controller!),
            ),
          ),

          // Central Play / Pause Button
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: InkWell(
                onTap: _togglePlayPause,
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isFinished
                        ? Icons.replay_rounded
                        : isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // Bottom Controls Bar
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Scrubber Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          trackHeight: 3,
                          activeTrackColor: Colors.blueAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.blueAccent,
                        ),
                        child: Slider(
                          value: value.position.inMilliseconds
                              .clamp(0, value.duration.inMilliseconds)
                              .toDouble(),
                          min: 0.0,
                          max: value.duration.inMilliseconds.toDouble() > 0
                              ? value.duration.inMilliseconds.toDouble()
                              : 1.0,
                          onChanged: (pos) {
                            _controller!.seekTo(Duration(milliseconds: pos.toInt()));
                            _showControlsTemporarily();
                          },
                        ),
                      ),
                      // Time & Action Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: _togglePlayPause,
                              ),
                              Text(
                                '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(
                              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: Colors.white,
                            ),
                            tooltip: _isMuted ? 'Nyalakan Suara' : 'Bisukan Suara',
                            onPressed: _toggleMute,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
