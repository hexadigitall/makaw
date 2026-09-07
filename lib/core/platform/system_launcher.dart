import 'dart:io';

/// Launches Windows OS utilities from the app, scoped to the real system like
/// any native desktop app (File Explorer, Run dialog, Task Manager, Settings,
/// consoles at a folder, ...). No-op on platforms without these utilities.
class SystemLauncher {
  SystemLauncher._();

  static bool get available => Platform.isWindows;

  /// Runs [command] detached from the app, exactly like clicking it in
  /// Windows would. Uses `start` so console/app windows appear on screen.
  static Future<void> launch(String command) async {
    if (!available) return;
    try {
      await Process.run('cmd.exe', ['/c', 'start', '', command]);
    } catch (_) {}
  }

  /// Opens a folder in File Explorer (defaults to This PC overview when
  /// [path] is null).
  static Future<void> openExplorer([String? path]) =>
      launch(path == null ? 'explorer.exe' : 'explorer.exe "$path"');

  static Future<void> openThisPc() => launch('explorer.exe shell:MyComputerFolder');

  static Future<void> openRecycleBin() => launch('explorer.exe shell:RecycleBinFolder');

  static Future<void> openDownloads() {
    final dl = Platform.environment['USERPROFILE'];
    return dl == null ? openThisPc() : openExplorer('$dl\\Downloads');
  }

  /// Opens a new Command Prompt console sitting at [path].
  static Future<void> openTerminalAt(String path) =>
      launch('cmd.exe /k "cd /d $path"');

  /// Opens a new PowerShell console sitting at [path].
  static Future<void> openPowerShellAt(String path) {
    final cmd = path.replaceAll("'", "''");
    return launch('powershell.exe -NoExit -Command "Set-Location -LiteralPath \'$cmd\'"');
  }

  static Future<void> openRunDialog() =>
      launch('rundll32.exe shell32.dll,OpenAs_RunDLL');

  static Future<void> openTaskManager() => launch('taskmgr.exe');

  static Future<void> openSettings() => launch('ms-settings:');

  static Future<void> openDisplaySettings() => launch('ms-settings:display');

  static Future<void> openStorageSettings() => launch('ms-settings:storagesense');

  static Future<void> openDeviceManager() => launch('devmgmt.msc');

  static Future<void> openDiskManagement() => launch('diskmgmt.msc');

  static Future<void> openControlPanel() => launch('control.exe');

  static Future<void> openSystemInfo() => launch('msinfo32.exe');

  static Future<void> openNotepad() => launch('notepad.exe');

  static Future<void> openCalculator() => launch('calc.exe');
}