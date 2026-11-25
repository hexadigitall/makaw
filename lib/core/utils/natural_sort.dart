/// Natural sorting utility that orders numbers (0-9) first, then A-Z,
/// with numerical chunk comparison (e.g., "Episode 2" < "Episode 10").
int naturalCompare(String a, String b) {
  if (identical(a, b)) return 0;
  if (a.isEmpty && b.isEmpty) return 0;
  if (a.isEmpty) return 1;
  if (b.isEmpty) return -1;

  final trimmedA = a.trim();
  final trimmedB = b.trim();
  if (trimmedA.isEmpty || trimmedB.isEmpty) {
    return trimmedA.compareTo(trimmedB);
  }

  // Determine top-level character classification:
  // Rank 0: digits (0-9)
  // Rank 1: letters (a-z, A-Z)
  // Rank 2: other punctuation / symbols
  final rankA = _charRank(trimmedA.codeUnitAt(0));
  final rankB = _charRank(trimmedB.codeUnitAt(0));
  if (rankA != rankB) {
    return rankA.compareTo(rankB);
  }

  // Tokenize both strings into alternating text and number chunks
  final chunksA = _tokenize(trimmedA);
  final chunksB = _tokenize(trimmedB);

  final len = chunksA.length < chunksB.length ? chunksA.length : chunksB.length;
  for (int i = 0; i < len; i++) {
    final itemA = chunksA[i];
    final itemB = chunksB[i];

    if (itemA is BigInt && itemB is BigInt) {
      final cmp = itemA.compareTo(itemB);
      if (cmp != 0) return cmp;
    } else {
      final strA = itemA.toString().toLowerCase();
      final strB = itemB.toString().toLowerCase();
      final cmp = strA.compareTo(strB);
      if (cmp != 0) return cmp;
    }
  }

  // Length fallback if one is a prefix of the other
  if (chunksA.length != chunksB.length) {
    return chunksA.length.compareTo(chunksB.length);
  }

  return trimmedA.compareTo(trimmedB);
}

int _charRank(int codeUnit) {
  if (codeUnit >= 48 && codeUnit <= 57) return 0; // '0'-'9'
  if ((codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122)) return 1; // 'A'-'Z', 'a'-'z'
  return 2;
}

List<dynamic> _tokenize(String s) {
  final chunks = <dynamic>[];
  final buffer = StringBuffer();
  bool? inDigit;

  for (int i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    final isDigit = code >= 48 && code <= 57;

    if (inDigit == null) {
      inDigit = isDigit;
      buffer.writeCharCode(code);
    } else if (inDigit == isDigit) {
      buffer.writeCharCode(code);
    } else {
      final text = buffer.toString();
      if (inDigit) {
        chunks.add(BigInt.tryParse(text) ?? text);
      } else {
        chunks.add(text);
      }
      buffer.clear();
      inDigit = isDigit;
      buffer.writeCharCode(code);
    }
  }

  if (buffer.isNotEmpty) {
    final text = buffer.toString();
    if (inDigit == true) {
      chunks.add(BigInt.tryParse(text) ?? text);
    } else {
      chunks.add(text);
    }
  }

  return chunks;
}
