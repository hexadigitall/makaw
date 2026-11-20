/// Utility to exclude system files, hidden files, and sensitive credentials
/// from file discovery, document scanning, and recents tracking.
///
/// Mandated by Makaw PRD v1.0 Section 1 & Decision Matrix:
/// - "Documents: system files leaked (desktop.ini), sensitive file shown in Recents (Chrome Passwords2.csv)"
/// - "Indexing: Scanner, hash, dedup, exclusion, sensitive filter. FORBIDDEN: Scanning system files."
class FileExclusionFilter {
  FileExclusionFilter._();

  /// Known OS system and metadata file basenames (case-insensitive).
  static const Set<String> _systemFileBasenames = {
    'desktop.ini',
    'thumbs.db',
    '.ds_store',
    'autorun.inf',
    'bootmgr',
    'bootnxt',
    'pagefile.sys',
    'swapfile.sys',
    'hiberfil.sys',
    'ntuser.dat',
    'ntuser.ini',
  };

  /// System directory names that should be pruned entirely during filesystem scans.
  static const Set<String> _systemDirectoryNames = {
    '.git',
    '.github',
    '.dart_tool',
    '.idea',
    '.vscode',
    '.opencode',
    'node_modules',
    'build',
    'dist',
    'cache',
    'tmp',
    'temp',
    'appdata',
    'windows',
    'program files',
    'program files (x86)',
    'system volume information',
    r'$recycle.bin',
  };

  /// File extensions that signify secrets, keys, or credentials.
  static const Set<String> _sensitiveExtensions = {
    '.pem',
    '.key',
    '.p12',
    '.pfx',
    '.jks',
    '.keystore',
    '.ovpn',
    '.pkcs12',
  };

  /// Keywords in filenames that indicate credentials or secrets.
  static final RegExp _sensitiveKeywordsRegex = RegExp(
    r'(password|credential|secret|token|id_rsa|id_ed25519|id_ecdsa|id_dsa)',
    caseSensitive: false,
  );

  /// Checks if a file or directory basename belongs to OS system metadata or is hidden.
  static bool isSystemOrHidden(String pathOrName) {
    final name = _basename(pathOrName);
    if (name.isEmpty) return false;

    // Unix-style hidden file / folder (.git, .DS_Store, etc.)
    if (name.startsWith('.')) return true;

    // Windows temporary / backup lockfiles
    if (name.startsWith(r'~$') || name.startsWith(r'.~') || name.endsWith('.tmp') || name.endsWith('.crdownload')) {
      return true;
    }

    final lower = name.toLowerCase();
    if (_systemFileBasenames.contains(lower)) return true;
    if (lower.startsWith('ntuser.dat')) return true;

    return false;
  }

  /// Checks if a directory should be skipped during recursive traversal.
  static bool isSystemDirectory(String dirName) {
    final name = _basename(dirName).toLowerCase();
    if (name.startsWith('.')) return true;
    return _systemDirectoryNames.contains(name);
  }

  /// Checks if a file likely contains sensitive credentials, keys, or exported passwords.
  static bool isSensitive(String pathOrName) {
    final name = _basename(pathOrName);
    final lower = name.toLowerCase();

    // Sensitive extensions (.key, .pem, .jks, etc.)
    for (final ext in _sensitiveExtensions) {
      if (lower.endsWith(ext)) return true;
    }

    // Dotenv files (.env, .env.local, .env.production)
    if (lower == '.env' || lower.startsWith('.env.')) return true;

    // Keywords like "Chrome Passwords.csv" or "aws_credentials.json"
    if (_sensitiveKeywordsRegex.hasMatch(lower)) return true;

    return false;
  }

  /// Returns true if the file should be excluded from search, scanner, and recents lists.
  static bool shouldExclude(String pathOrName) {
    return isSystemOrHidden(pathOrName) || isSensitive(pathOrName);
  }

  static String _basename(String path) {
    final clean = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final idx = clean.lastIndexOf('/');
    return idx >= 0 ? clean.substring(idx + 1) : clean;
  }
}
