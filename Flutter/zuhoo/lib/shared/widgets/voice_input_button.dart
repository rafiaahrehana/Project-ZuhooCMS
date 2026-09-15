import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// A mic button that dictates into whatever [controller] it's paired with.
///
/// Angular's `SpeechInputService` wraps the browser's Web Speech API for the
/// same purpose in the AI assistant's chat box — a phone's own on-device
/// recognizer is the mobile-native equivalent, not a port of anything, since
/// there is no "browser" layer here to wrap.
///
/// One recognizer per button rather than a shared singleton: two composers
/// existing on screen at once should not be able to fight over the same
/// microphone session.
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({super.key, required this.controller, this.color});

  final TextEditingController controller;
  final Color? color;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final _speech = stt.SpeechToText();
  bool _listening = false;

  /// What was already typed when listening started — dictation is added to
  /// it, not over it, so tapping the mic mid-sentence does not erase the
  /// part typed by hand.
  String _base = '';

  @override
  void dispose() {
    if (_listening) _speech.stop();
    super.dispose();
  }

  void _apply(String recognized) {
    final text = _base.isEmpty ? recognized : '$_base $recognized';
    widget.controller
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final ready = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start voice input — check the microphone permission.',
          ),
        ),
      );
      return;
    }

    _base = widget.controller.text;
    setState(() => _listening = true);
    await _speech.listen(onResult: (result) => _apply(result.recognizedWords));
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context);
    return IconButton(
      icon: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded),
      color: _listening ? bos.colorScheme.error : widget.color,
      tooltip: _listening ? 'Stop dictating' : 'Speak instead of typing',
      onPressed: _toggle,
    );
  }
}
