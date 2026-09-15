import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';

/// The search box that sits above a list.
///
/// Debounced, because every list this app searches is a server round trip and
/// the naive version fires one per keystroke — eight requests to type
/// "engineer", of which seven are already stale by the time they answer, and
/// whose replies can land out of order and show the wrong result for the text
/// on screen. The delay is short enough to feel immediate and long enough that
/// ordinary typing produces one call.
///
/// The clear button is deliberately part of the field rather than something
/// the caller adds: a search with no way back to the unfiltered list is a trap
/// on a phone, where there is no Escape key.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.initial,
    this.debounce = const Duration(milliseconds: 350),
    this.autofocus = false,
  });

  /// Called with the trimmed query after [debounce] has elapsed, and
  /// immediately with an empty string when the field is cleared — clearing is
  /// an explicit act and should not wait.
  final ValueChanged<String> onChanged;
  final String hint;
  final String? initial;
  final Duration debounce;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  Timer? _timer;

  /// Tracked so the clear button appears and disappears without rebuilding on
  /// every keystroke for any other reason.
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = (widget.initial ?? '').isNotEmpty;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final hasText = raw.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);

    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(raw.trim()));
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    setState(() => _hasText = false);
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      // Submitting should not wait out the debounce that is already pending.
      onSubmitted: (value) {
        _timer?.cancel();
        widget.onChanged(value.trim());
      },
      style: TextStyle(color: bos.text, fontSize: 14.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: TextStyle(color: bos.muted, fontSize: 14.5),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: bos.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: _hasText
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: bos.muted,
                onPressed: _clear,
                tooltip: 'Clear search',
                // Sizes the ink splash, not the tap target: IconButton's
                // tap padding keeps that at 48 whatever this says. See
                // tap_target_test.dart, which measures it.
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
              )
            : null,
        filled: true,
        fillColor: bos.bgCard,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: bos.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: bos.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: bos.brand, width: 1.5),
        ),
      ),
    );
  }
}
