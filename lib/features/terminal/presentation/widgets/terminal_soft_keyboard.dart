import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Two-row thumb-first Mobile Soft-Key Bar, Symbol Dock, and Cursor Trackpad
/// for Makaw Terminal 2.0.
///
/// Supports sticky `CTRL` and `ALT` modifiers, hardware/xterm arrow & escape
/// keys (`Terminal.keyInput`), clipboard paste/copy, expandable developer symbols
/// (`/` `-` `|` `~` `{` `}` `&&` `;`), and a horizontal drag strip that sends
/// precise left/right cursor movement steps without tapping tiny arrows.
class TerminalSoftKeyboard extends StatefulWidget {
  final Terminal terminal;
  final TerminalController controller;
  final VoidCallback onCopySelection;
  final VoidCallback onPasteClipboard;
  final VoidCallback onClear;
  final VoidCallback onOpenHosts;
  final VoidCallback onToggleFind;
  final bool showRow2;
  final ValueChanged<bool> onToggleRow2;

  const TerminalSoftKeyboard({
    super.key,
    required this.terminal,
    required this.controller,
    required this.onCopySelection,
    required this.onPasteClipboard,
    required this.onClear,
    required this.onOpenHosts,
    required this.onToggleFind,
    required this.showRow2,
    required this.onToggleRow2,
  });

  @override
  State<TerminalSoftKeyboard> createState() => _TerminalSoftKeyboardState();
}

class _TerminalSoftKeyboardState extends State<TerminalSoftKeyboard> {
  bool _ctrlArmed = false;
  bool _altArmed = false;
  bool _showCommandBar = false;
  final TextEditingController _cmdCtrl = TextEditingController();
  double _trackpadAccumDx = 0;

  @override
  void dispose() {
    _cmdCtrl.dispose();
    super.dispose();
  }

  void _sendSpecialKey(TerminalKey key) {
    HapticFeedback.selectionClick();
    widget.terminal.keyInput(
      key,
      ctrl: _ctrlArmed,
      alt: _altArmed,
    );
    if (_ctrlArmed || _altArmed) {
      setState(() {
        _ctrlArmed = false;
        _altArmed = false;
      });
    }
  }

  void _sendText(String text) {
    HapticFeedback.selectionClick();
    if (_ctrlArmed && text.length == 1) {
      final code = text.toUpperCase().codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        widget.terminal.onOutput?.call(String.fromCharCode(code - 64));
        setState(() {
          _ctrlArmed = false;
          _altArmed = false;
        });
        return;
      }
    }
    if (_altArmed) {
      widget.terminal.onOutput?.call('\x1b$text');
      setState(() {
        _ctrlArmed = false;
        _altArmed = false;
      });
      return;
    }
    widget.terminal.onOutput?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF0F172A);
    final border = Colors.white.withValues(alpha: 0.08);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showCommandBar)
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              decoration: BoxDecoration(
                color: const Color(0xFF090D16),
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cmdCtrl,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type or paste command cleanly…',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        final cmd = v;
                        _cmdCtrl.clear();
                        widget.terminal.onOutput?.call('\x03$cmd\r');
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () {
                      final cmd = _cmdCtrl.text;
                      _cmdCtrl.clear();
                      widget.terminal.onOutput?.call('$cmd\r');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF090D16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Run',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          // Row 1: Essential terminal control + navigation keys
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              children: [
                _iconCap(Icons.backspace_outlined,
                    tooltip: 'Backspace',
                    onTap: () => _sendSpecialKey(TerminalKey.backspace)),
                _keyCap('ESC', onTap: () => _sendSpecialKey(TerminalKey.escape)),
                _keyCap('TAB', onTap: () => _sendSpecialKey(TerminalKey.tab)),
                _modCap(
                  'CTRL',
                  active: _ctrlArmed,
                  onTap: () => setState(() => _ctrlArmed = !_ctrlArmed),
                ),
                _modCap(
                  'ALT',
                  active: _altArmed,
                  onTap: () => setState(() => _altArmed = !_altArmed),
                ),
                _keyCap('^C',
                    color: const Color(0xFFF87171),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.terminal.onOutput?.call('\x03');
                    }),
                _iconCap(Icons.keyboard_arrow_up,
                    tooltip: 'Up',
                    onTap: () => _sendSpecialKey(TerminalKey.arrowUp)),
                _iconCap(Icons.keyboard_arrow_down,
                    tooltip: 'Down',
                    onTap: () => _sendSpecialKey(TerminalKey.arrowDown)),
                _iconCap(Icons.keyboard_arrow_left,
                    tooltip: 'Left',
                    onTap: () => _sendSpecialKey(TerminalKey.arrowLeft)),
                _iconCap(Icons.keyboard_arrow_right,
                    tooltip: 'Right',
                    onTap: () => _sendSpecialKey(TerminalKey.arrowRight)),
                _iconCap(
                  Icons.edit_note_rounded,
                  tooltip: 'Command box',
                  highlight: _showCommandBar,
                  onTap: () => setState(() => _showCommandBar = !_showCommandBar),
                ),
                _iconCap(
                  widget.showRow2
                      ? Icons.keyboard_arrow_down
                      : Icons.tune,
                  tooltip: widget.showRow2 ? 'Hide symbols' : 'Symbols & tools',
                  highlight: widget.showRow2,
                  onTap: () => widget.onToggleRow2(!widget.showRow2),
                ),
              ],
            ),
          ),

          // Row 2 (collapsible): Symbols, clipboard, hosts, search & cursor trackpad
          if (widget.showRow2)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
                children: [
                  for (final sym in const ['/', '-', '|', '~', r'$', '{', '}', '&&', ';', '"'])
                    _keyCap(sym, minWidth: 32, onTap: () => _sendText(sym)),
                  const SizedBox(width: 4),
                  _actionPill(Icons.paste_rounded, 'Paste', widget.onPasteClipboard),
                  _actionPill(Icons.copy_rounded, 'Copy', widget.onCopySelection),
                  _actionPill(Icons.search_rounded, 'Find', widget.onToggleFind),
                  _actionPill(Icons.dns_outlined, 'Hosts', widget.onOpenHosts),
                  _actionPill(Icons.cleaning_services_outlined, 'Clear', widget.onClear),
                ],
              ),
            ),

          // Compact horizontal swipe trackpad for fine cursor positioning
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              _trackpadAccumDx += details.delta.dx;
              const step = 14.0;
              while (_trackpadAccumDx >= step) {
                _trackpadAccumDx -= step;
                widget.terminal.keyInput(TerminalKey.arrowRight);
              }
              while (_trackpadAccumDx <= -step) {
                _trackpadAccumDx += step;
                widget.terminal.keyInput(TerminalKey.arrowLeft);
              }
            },
            onHorizontalDragEnd: (_) => _trackpadAccumDx = 0,
            child: Container(
              height: 20,
              width: double.infinity,
              alignment: Alignment.center,
              color: const Color(0xFF090D16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.drag_handle_rounded,
                      size: 13, color: Colors.white.withValues(alpha: 0.28)),
                  const SizedBox(width: 6),
                  Text(
                    _ctrlArmed
                        ? 'CTRL armed — tap a key'
                        : (_altArmed
                            ? 'ALT armed — tap a key'
                            : 'Swipe to move cursor'),
                    style: TextStyle(
                      fontSize: 10,
                      color: (_ctrlArmed || _altArmed)
                          ? const Color(0xFF38BDF8)
                          : Colors.white38,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyCap(
    String label, {
    required VoidCallback onTap,
    Color? color,
    double minWidth = 40,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minWidth: minWidth),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: color ?? Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modCap(
    String label, {
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Material(
        color: active ? const Color(0xFF38BDF8) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF090D16) : const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconCap(
    IconData icon, {
    required VoidCallback onTap,
    String? tooltip,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: highlight
              ? const Color(0xFF38BDF8).withValues(alpha: 0.2)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: SizedBox(
              width: 36,
              child: Icon(
                icon,
                size: 17,
                color: highlight ? const Color(0xFF38BDF8) : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionPill(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Material(
        color: const Color(0xFF172554).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: const Color(0xFF60A5FA)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFDBEAFE),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
