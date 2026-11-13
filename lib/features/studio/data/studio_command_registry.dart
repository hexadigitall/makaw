import 'package:flutter/material.dart';

/// A single action surfaced in the Commander (Ctrl+Shift+P) palette.
class IdeCommand {
  final String id;
  final String label;
  final String? category;
  final String? shortcut;
  final IconData icon;
  final VoidCallback action;

  const IdeCommand({
    required this.id,
    required this.label,
    this.category,
    this.shortcut,
    this.icon = Icons.terminal,
    required this.action,
  });
}

/// Central registry of all Studio commands. The Command Palette and any
/// keyboard shortcut resolve through these entries, so actions stay
/// discoverable and consistent across views.
class StudioCommandRegistry {
  StudioCommandRegistry._();

  /// Builds the command set wired to [callbacks]. Returns a fresh list each
  /// call so the registry can hold closures over the owning screen state.
  static List<IdeCommand> commands({
    required VoidCallback runBuild,
    required VoidCallback openTerminal,
    required VoidCallback toggleTerminalPanel,
    required VoidCallback togglePreview,
    required VoidCallback newFile,
    required VoidCallback saveFile,
    required VoidCallback backToHub,
  }) {
    return [
      IdeCommand(
        id: 'run.build',
        label: 'Run Build',
        category: 'Run',
        shortcut: '',
        icon: Icons.play_arrow_rounded,
        action: runBuild,
      ),
      IdeCommand(
        id: 'terminal.new',
        label: 'New Terminal',
        category: 'Terminal',
        shortcut: '',
        icon: Icons.terminal,
        action: openTerminal,
      ),
      IdeCommand(
        id: 'view.terminal',
        label: 'Toggle Terminal Panel',
        category: 'View',
        shortcut: 'Ctrl+J',
        icon: Icons.terminal,
        action: toggleTerminalPanel,
      ),
      IdeCommand(
        id: 'view.preview',
        label: 'Toggle Live Preview',
        category: 'View',
        shortcut: '',
        icon: Icons.splitscreen,
        action: togglePreview,
      ),
      IdeCommand(
        id: 'file.new',
        label: 'New File',
        category: 'File',
        shortcut: '',
        icon: Icons.note_add_outlined,
        action: newFile,
      ),
      IdeCommand(
        id: 'file.save',
        label: 'Save',
        category: 'File',
        shortcut: 'Ctrl+S',
        icon: Icons.save_outlined,
        action: saveFile,
      ),
      IdeCommand(
        id: 'studio.hub',
        label: 'Back to Code Studio Hub',
        category: 'Studio',
        shortcut: '',
        icon: Icons.widgets_outlined,
        action: backToHub,
      ),
    ];
  }
}