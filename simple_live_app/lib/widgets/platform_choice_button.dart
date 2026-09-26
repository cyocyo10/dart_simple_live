import 'package:flutter/material.dart';

bool isDesktopPlatform(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };

/// Desktop choices stay anchored to their button, including in narrow windows.
class PlatformChoiceButton extends StatefulWidget {
  const PlatformChoiceButton({
    super.key,
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    required this.onMobilePressed,
    this.onOpened,
    this.onClosed,
  });
  final String label;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onMobilePressed;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  @override
  State<PlatformChoiceButton> createState() => _PlatformChoiceButtonState();
}

class _PlatformChoiceButtonState extends State<PlatformChoiceButton> {
  ValueChanged<int>? _openSelection;
  VoidCallback? _openClosed;
  int _openIndex = -1;

  void _opened() {
    // PopupMenuButton uses its latest widget callback when the menu closes.
    // Keep the callback that owns the option snapshot actually shown to users.
    _openSelection = widget.onSelected;
    _openClosed = widget.onClosed;
    _openIndex = widget.selectedIndex;
    widget.onOpened?.call();
  }

  void _closed() {
    final callback = _openClosed;
    _openSelection = null;
    _openClosed = null;
    callback?.call();
  }

  void _selected(int index) {
    final callback = _openSelection;
    final changed = index != _openIndex;
    _closed();
    if (changed) callback?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white, fontSize: 15),
    );
    if (!isDesktopPlatform(context)) {
      return TextButton(onPressed: widget.onMobilePressed, child: text);
    }
    return PopupMenuButton<int>(
      tooltip: widget.options.isEmpty ? '暂无可选项' : widget.label,
      enabled: widget.options.isNotEmpty,
      initialValue: widget.selectedIndex,
      requestFocus: true,
      onOpened: _opened,
      onCanceled: _closed,
      onSelected: _selected,
      itemBuilder: (_) => [
        for (var i = 0; i < widget.options.length; i++)
          CheckedPopupMenuItem<int>(
            value: i,
            checked: i == widget.selectedIndex,
            child: Text(widget.options[i]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            text,
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
