import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../widgets/camera_preview_fitted.dart';

/// Full-screen camera recorder. Stops automatically after [maxSeconds].
/// Pops with the recorded [XFile], or `null` if cancelled / error.
class ShortVideoRecordPage extends StatefulWidget {
  const ShortVideoRecordPage({
    super.key,
    this.maxSeconds = 10,
  });

  final int maxSeconds;

  @override
  State<ShortVideoRecordPage> createState() => _ShortVideoRecordPageState();
}

class _ShortVideoRecordPageState extends State<ShortVideoRecordPage> {
  CameraController? _controller;
  bool _initializing = true;
  String? _error;
  bool _recording = false;
  int _elapsedSeconds = 0;
  Timer? _tick;
  Timer? _maxTimer;
  DateTime? _recordStartedAt;
  bool _stopping = false;

  @override
  void dispose() {
    _tick?.cancel();
    _maxTimer?.cancel();
    final c = _controller;
    if (c != null && c.value.isRecordingVideo) {
      c.stopVideoRecording().then((_) {}, onError: (_) {});
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      setState(() {
        _initializing = false;
        _error = 'Camera and microphone permission are required to record.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'No camera found on this device.';
        });
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not start camera: $e';
      });
    }
  }

  Future<void> _toggleRecord() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (_recording) {
      await _stopRecording(manual: true);
      return;
    }

    await c.prepareForVideoRecording();
    await c.startVideoRecording();
    _recordStartedAt = DateTime.now();
    setState(() {
      _recording = true;
      _elapsedSeconds = 0;
    });

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording) return;
      setState(() {
        _elapsedSeconds += 1;
      });
    });

    _maxTimer = Timer(Duration(seconds: widget.maxSeconds), () {
      _stopRecording(manual: false);
    });
  }

  Future<void> _stopRecording({required bool manual}) async {
    if (_stopping) return;
    _stopping = true;
    _maxTimer?.cancel();
    _maxTimer = null;
    _tick?.cancel();
    _tick = null;

    final c = _controller;
    if (c == null || !c.value.isRecordingVideo) {
      _stopping = false;
      if (mounted) setState(() => _recording = false);
      return;
    }

    try {
      final file = await c.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      final started = _recordStartedAt;
      _recordStartedAt = null;
      if (started != null) {
        final actual = DateTime.now().difference(started).inSeconds.clamp(1, widget.maxSeconds);
        Navigator.of(context).pop(RecordedClip(file: file, durationSeconds: actual));
        return;
      }
      Navigator.of(context).pop(RecordedClip(file: file, durationSeconds: widget.maxSeconds));
    } catch (e) {
      if (!mounted) return;
      setState(() => _recording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save recording: $e')),
      );
    } finally {
      _stopping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Record up to ${widget.maxSeconds}s'),
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: CameraPreviewFitted(controller: _controller!),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(
                            _recording
                                ? 'Recording… $_elapsedSeconds / ${widget.maxSeconds}s (stops automatically)'
                                : 'Tap the button to start. Recording stops at ${widget.maxSeconds} seconds.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                              ),
                              GestureDetector(
                                onTap: _toggleRecord,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 4),
                                    color: _recording ? Colors.red : Colors.white24,
                                  ),
                                  child: Icon(
                                    _recording ? Icons.stop : Icons.fiber_manual_record,
                                    color: _recording ? Colors.white : Colors.red,
                                    size: 36,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 80),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class RecordedClip {
  RecordedClip({
    required this.file,
    required this.durationSeconds,
  });

  final XFile file;
  final int durationSeconds;
}
