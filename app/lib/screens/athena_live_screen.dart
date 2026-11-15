import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/voice.dart';
import '../theme.dart';
import '../widgets/athena_chat.dart' show athenaIcon;

/// Athena Live: a video call with Athena inside the app.
/// The camera fills the screen. The person points it at an item and taps a quick
/// question (always on screen) or types one. The app takes one picture, the server asks
/// Groq about it, and the answer shows as a caption and is read out loud by the phone's
/// own voice (no audio leaves the phone). Nothing is recorded or stored.
/// The camera runs only while this screen is open; the microphone is never used.
class AthenaLiveScreen extends StatefulWidget {
  const AthenaLiveScreen({super.key, required this.api});

  final Api api;

  /// Quick questions, shown for the whole call.
  static const quickQuestions = ['What is this?', 'Can I drink it?', 'Can I touch it?'];

  @override
  State<AthenaLiveScreen> createState() => _AthenaLiveScreenState();
}

class _AthenaLiveScreenState extends State<AthenaLiveScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  List<CameraDescription> _cameras = const [];
  CameraController? _camera;
  int _cameraIndex = 0;

  /// Shown in the caption box: what is happening, what was asked, Athena's answer.
  String _status = 'Starting the camera…';
  String? _asked;
  String? _answer;
  bool _offline = false;
  bool _busy = false;
  String? _previousQuestion;

  final _started = DateTime.now();
  Timer? _clock;

  /// Athena's voice: Apple's built-in text-to-speech (see services/voice.dart).
  bool _speaking = false;
  bool _muted = false;
  int _speech = 0; // which answer is being spoken; an older one finishing is ignored

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _stopSpeaking();
    _camera?.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    if (_muted || text.isEmpty || !Voice.available) return;
    final speech = ++_speech;
    setState(() => _speaking = true);
    await Voice.speak(text); // returns when Athena finishes or is cut off
    if (mounted && speech == _speech) setState(() => _speaking = false);
  }

  void _stopSpeaking() {
    _speech++;
    _speaking = false;
    Voice.stop();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_muted) {
      setState(_stopSpeaking);
    } else if (_answer != null && !_offline) {
      _speak(_answer!);
    }
  }

  /// iOS takes the camera away when the app goes to the background. Give it back after.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopSpeaking();
      _camera = null;
      camera?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && camera == null && _cameras.isNotEmpty) {
      _openCamera(_cameras[_cameraIndex]);
    }
  }

  Future<void> _startCamera() async {
    try {
      _cameras = await availableCameras();
    } catch (_) {
      _cameras = const [];
    }
    if (_cameras.isEmpty) {
      if (mounted) setState(() => _status = 'No camera found on this device.');
      return;
    }
    // Start with the back camera: the person shows Athena an item, not their face.
    final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    _cameraIndex = back < 0 ? 0 : back;
    await _openCamera(_cameras[_cameraIndex]);
  }

  Future<void> _openCamera(CameraDescription description) async {
    final controller = CameraController(
      description,
      ResolutionPreset.medium, // small pictures: fast to send, enough to read a label
      enableAudio: false, // never the microphone
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
    } on CameraException catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _status = error.code.contains('Denied')
          ? 'Camera blocked. Allow the camera for Cycl0ps in Settings.'
          : 'The camera could not start.');
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    final old = _camera;
    setState(() {
      _camera = controller;
      if (_answer == null) _status = 'Hold a label close to the camera, then ask.';
    });
    await old?.dispose();
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _busy) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    final old = _camera;
    setState(() => _camera = null);
    await old?.dispose();
    await _openCamera(_cameras[_cameraIndex]);
  }

  Future<void> _ask(String text) async {
    final question = text.trim();
    final camera = _camera;
    if (question.isEmpty || _busy) return;
    if (camera == null || !camera.value.isInitialized) {
      setState(() => _status = 'Wait for the camera to start.');
      return;
    }
    FocusScope.of(context).unfocus();
    _text.clear();
    _stopSpeaking(); // a new question interrupts the old answer
    setState(() {
      _busy = true;
      _asked = question;
      _answer = null;
      _offline = false;
      _status = 'Athena is looking…';
    });
    try {
      final picture = await camera.takePicture();
      final image = base64Encode(await picture.readAsBytes());
      final answer = await widget.api.athenaLook(
        imageBase64: image,
        question: question,
        previousQuestion: _previousQuestion,
      );
      if (!mounted) return;
      _previousQuestion = question;
      setState(() {
        _answer = answer.reply;
        _offline = answer.source != 'groq';
        _status = _offline ? 'Athena could not answer' : 'Athena';
      });
      if (!_offline) unawaited(_speak(answer.reply));
    } on ApiException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } on CameraException {
      if (mounted) setState(() => _status = 'Could not take a picture. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _callTime {
    final seconds = DateTime.now().difference(_started).inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    resizeToAvoidBottomInset: true,
    body: Stack(
      children: [
        Positioned.fill(child: _preview()),
        // Dark fades so white text stays readable over any picture.
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 140,
          child: _Fade(begin: Alignment.topCenter),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 380,
          child: _Fade(begin: Alignment.bottomCenter),
        ),
        SafeArea(
          child: Column(
            children: [
              _topBar(),
              const Spacer(),
              _captions(),
              const SizedBox(height: 12),
              _quickQuestions(),
              const SizedBox(height: 10),
              _askBar(),
              const SizedBox(height: 14),
              _controls(),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _preview() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return Container(
        color: BB.ink,
        alignment: Alignment.center,
        child: const Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 56),
      );
    }
    // Fill the screen like a video call (crop the edges, don't squash).
    final size = camera.value.previewSize;
    if (size == null) return CameraPreview(camera);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // The camera reports landscape sizes; the phone shows it upright.
          width: size.height,
          height: size.width,
          child: CameraPreview(camera),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: BB.ink,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 2),
          ),
          child: const Icon(athenaIcon, color: BB.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Athena', style: heading(19, color: BB.white)),
              Text(
                'Live assistant · $_callTime',
                style: body(13, color: Colors.white70),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 9,
                color: _camera == null ? Colors.white54 : const Color(0xFF4ADE80),
              ),
              const SizedBox(width: 6),
              Text(
                _camera == null ? 'Camera off' : 'Live',
                style: body(13, color: BB.white, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _captions() => Container(
    width: double.infinity,
    constraints: const BoxConstraints(maxWidth: 640, maxHeight: 220),
    margin: const EdgeInsets.symmetric(horizontal: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(18),
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (_busy) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                ),
                const SizedBox(width: 8),
              ],
              if (_offline) ...[
                const Icon(Icons.cloud_off_outlined, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
              ],
              if (_speaking) ...[
                const Icon(Icons.graphic_eq, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  _speaking ? 'Athena is speaking' : _status,
                  style: body(13, color: Colors.white70),
                ),
              ),
            ],
          ),
          if (_asked != null) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: 'You: ', style: body(14, color: BB.white, weight: FontWeight.w700)),
                TextSpan(text: _asked, style: body(14, color: Colors.white70)),
              ]),
            ),
          ],
          if (_answer != null) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(_answer!, style: body(18, color: BB.white, weight: FontWeight.w500)),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _quickQuestions() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final question in AthenaLiveScreen.quickQuestions)
          FilledButton(
            onPressed: _busy || _camera == null ? null : () => _ask(question),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              backgroundColor: BB.white,
              foregroundColor: BB.ink,
              disabledBackgroundColor: Colors.white30,
              disabledForegroundColor: Colors.white70,
              shape: const StadiumBorder(),
            ),
            child: Text(question, style: body(15, weight: FontWeight.w600)),
          ),
      ],
    ),
  );

  /// Type a question, or use the keyboard's microphone key to say it.
  Widget _askBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _text,
              enabled: !_busy,
              textInputAction: TextInputAction.send,
              onSubmitted: _ask,
              style: body(16, color: BB.white),
              cursorColor: BB.white,
              decoration: InputDecoration(
                hintText: 'Ask about what you see',
                hintStyle: body(16, color: Colors.white60),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton.filled(
              onPressed: _busy ? null : () => _ask(_text.text),
              tooltip: 'Ask Athena',
              style: IconButton.styleFrom(
                backgroundColor: BB.accent,
                foregroundColor: BB.white,
                disabledBackgroundColor: Colors.white24,
              ),
              icon: const Icon(Icons.send_outlined),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _controls() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // Voice buttons only where Athena can speak (the iPhone app, not the web page).
      if (Voice.available) ...[
        _roundButton(
          icon: Icons.replay,
          label: 'Replay',
          color: Colors.white24,
          onPressed: _answer != null && !_offline && !_busy && !_muted
              ? () => _speak(_answer!)
              : null,
        ),
        const SizedBox(width: 20),
        _roundButton(
          icon: _muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          label: _muted ? 'Unmute' : 'Mute',
          color: _muted ? BB.white : Colors.white24,
          iconColor: _muted ? BB.ink : BB.white,
          onPressed: _toggleMute,
        ),
        const SizedBox(width: 20),
      ],
      _roundButton(
        icon: Icons.cameraswitch_outlined,
        label: 'Flip',
        color: Colors.white24,
        onPressed: _cameras.length > 1 && !_busy ? _flipCamera : null,
      ),
      const SizedBox(width: 20),
      _roundButton(
        icon: Icons.call_end,
        label: 'End',
        color: BB.danger,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ],
  );

  Widget _roundButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    Color iconColor = BB.white,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 60,
        height: 60,
        child: IconButton.filled(
          onPressed: onPressed,
          tooltip: label,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: iconColor,
            disabledBackgroundColor: Colors.white12,
            disabledForegroundColor: Colors.white38,
          ),
          icon: Icon(icon, size: 28),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: body(13, color: Colors.white70)),
    ],
  );
}

class _Fade extends StatelessWidget {
  const _Fade({required this.begin});

  final Alignment begin;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: -begin,
          colors: const [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
    ),
  );
}
