import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/terminal_models.dart';

/// Generated pure-Dart OpenSSH Ed25519 identity bundle.
class GeneratedSshIdentity {
  final String privateKeyPem;
  final String publicKeyOpenSsh;
  final String sha256Fingerprint;

  const GeneratedSshIdentity({
    required this.privateKeyPem,
    required this.publicKeyOpenSsh,
    required this.sha256Fingerprint,
  });
}

/// Encrypted vault for saved SSH servers/workstations and SSH identities.
///
/// Host profiles live in `SharedPreferences`; passwords, private PEM keys, and
/// key passphrases are persisted strictly inside `FlutterSecureStorage`. Includes
/// an in-memory fallback when running headless unit tests without platform
/// channels.
class SshVaultService {
  static const _hostsKey = 'makaw_ssh_hosts_v1';
  static const _secretPrefix = 'makaw_ssh_secret_v1_';

  final FlutterSecureStorage _secureStorage;
  final Map<String, String> _memoryFallback = {};
  List<SshHostProfile> _hosts = [];
  bool _loaded = false;

  SshVaultService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  List<SshHostProfile> get hosts => List.unmodifiable(_hosts);

  Future<List<SshHostProfile>> loadHosts() async {
    if (_loaded) return hosts;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_hostsKey);
      if (raw != null && raw.isNotEmpty) {
        _hosts = (jsonDecode(raw) as List)
            .map((e) => SshHostProfile.fromJson(e as Map<String, dynamic>))
            .where((h) => h.host.isNotEmpty)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    } catch (_) {}
    _loaded = true;
    return hosts;
  }

  SshHostProfile? findByIdOrName(String idOrName) {
    final q = idOrName.trim().toLowerCase();
    for (final h in _hosts) {
      if (h.id.toLowerCase() == q ||
          h.name.toLowerCase() == q ||
          h.target.toLowerCase() == q) {
        return h;
      }
    }
    return null;
  }

  Future<void> _persistHosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _hostsKey, jsonEncode(_hosts.map((h) => h.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _writeSecret(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _memoryFallback.remove(key);
      try {
        await _secureStorage.delete(key: key);
      } catch (_) {}
      return;
    }
    _memoryFallback[key] = value;
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (_) {}
  }

  Future<String?> _readSecret(String key) async {
    try {
      final v = await _secureStorage.read(key: key);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return _memoryFallback[key];
  }

  Future<SshHostProfile> saveHost(
    SshHostProfile host, {
    String? password,
    String? privateKeyPem,
    String? passphrase,
  }) async {
    await loadHosts();
    final id = host.id.isEmpty
        ? 'ssh_${DateTime.now().microsecondsSinceEpoch}'
        : host.id;
    final stored = SshHostProfile(
      id: id,
      name: host.name.trim().isEmpty ? host.displayTarget : host.name.trim(),
      host: host.host.trim(),
      port: host.port <= 0 ? 22 : host.port,
      username: host.username.trim().isEmpty ? 'root' : host.username.trim(),
      authMethod: host.authMethod,
      autoTmux: host.autoTmux,
      tmuxSession: host.tmuxSession.trim().isEmpty
          ? 'makaw'
          : host.tmuxSession.trim(),
      defaultRemoteDir: host.defaultRemoteDir.trim(),
      createdAt: host.createdAt,
    );

    _hosts = [
      stored,
      ..._hosts.where((h) => h.id != id),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _persistHosts();

    if (password != null) {
      await _writeSecret('${_secretPrefix}pw_$id', password);
    }
    if (privateKeyPem != null) {
      await _writeSecret('${_secretPrefix}key_$id', privateKeyPem.trim());
    }
    if (passphrase != null) {
      await _writeSecret('${_secretPrefix}pp_$id', passphrase);
    }
    return stored;
  }

  Future<void> removeHost(String id) async {
    await loadHosts();
    _hosts = _hosts.where((h) => h.id != id).toList();
    await _persistHosts();
    await _writeSecret('${_secretPrefix}pw_$id', null);
    await _writeSecret('${_secretPrefix}key_$id', null);
    await _writeSecret('${_secretPrefix}pp_$id', null);
  }

  Future<({String? password, String? privateKeyPem, String? passphrase})>
      readSecrets(String hostId) async {
    final pw = await _readSecret('${_secretPrefix}pw_$hostId');
    final key = await _readSecret('${_secretPrefix}key_$hostId');
    final pp = await _readSecret('${_secretPrefix}pp_$hostId');
    return (password: pw, privateKeyPem: key, passphrase: pp);
  }

  /// Generates a genuine OpenSSH Ed25519 keypair in pure Dart (zero native
  /// `ssh-keygen` binary required, identical on Android, Windows, Linux, macOS).
  static GeneratedSshIdentity generateEd25519KeyPair({
    String comment = 'makaw@device',
  }) {
    final rng = Random.secure();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    return deriveEd25519FromSeed(seed, comment: comment);
  }

  /// Derives a complete OpenSSH Ed25519 identity from a 32-byte private seed
  /// per RFC 8032 and serializes it via `dartssh2` `OpenSSHEd25519KeyPair`.
  static GeneratedSshIdentity deriveEd25519FromSeed(
    Uint8List seed, {
    String comment = 'makaw@device',
  }) {
    if (seed.length != 32) {
      throw ArgumentError.value(seed.length, 'seed.length', 'must be 32');
    }
    final digest = _PureSha512.hash(seed);
    final scalarBytes = Uint8List.fromList(digest.sublist(0, 32));
    scalarBytes[0] &= 248;
    scalarBytes[31] &= 127;
    scalarBytes[31] |= 64;

    final scalar = _bytesToBigIntLE(scalarBytes);
    final pubPoint = _Ed25519Curve.scalarMultBase(scalar);
    final pubBytes = _Ed25519Curve.encodePoint(pubPoint);

    // OpenSSH / NaCl Ed25519 private key format stores 64 bytes: seed || pubKey.
    final priv64 = Uint8List(64)
      ..setRange(0, 32, seed)
      ..setRange(32, 64, pubBytes);

    final pair = OpenSSHEd25519KeyPair(pubBytes, priv64, comment);
    final pem = pair.toPem();
    final pubWire = pair.toPublicKey().encode();
    final openSshPub =
        'ssh-ed25519 ${base64.encode(pubWire)} ${comment.trim()}'.trim();

    final sha256 = _PureSha256.hash(pubWire);
    final fpB64 = base64.encode(sha256).replaceAll('=', '');
    return GeneratedSshIdentity(
      privateKeyPem: pem,
      publicKeyOpenSsh: openSshPub,
      sha256Fingerprint: 'SHA256:$fpB64',
    );
  }

  static BigInt _bytesToBigIntLE(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }
}

/// Pure-Dart RFC 8032 Ed25519 extended-coordinates curve arithmetic (`p = 2^255 - 19`).
class _Ed25519Curve {
  static final BigInt p = (BigInt.one << 255) - BigInt.from(19);
  static final BigInt _d =
      (BigInt.from(-121665) * BigInt.from(121666).modInverse(p)) % p;
  static final BigInt _bx = BigInt.parse(
      '15112221349535400772501151409588531511454012693041857206046113283949847762202');
  static final BigInt _by = BigInt.parse(
      '46316835694926478169428394003475163141307993866256225615783033603165251855960');

  static _ExtPoint get _base => _ExtPoint(
        _bx % p,
        _by % p,
        BigInt.one,
        (_bx * _by) % p,
      );

  static _ExtPoint scalarMultBase(BigInt scalar) {
    var result = _ExtPoint(BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);
    var addend = _base;
    var k = scalar;
    while (k > BigInt.zero) {
      if (k.isOdd) result = _add(result, addend);
      addend = _add(addend, addend);
      k >>= 1;
    }
    return result;
  }

  static _ExtPoint _add(_ExtPoint p1, _ExtPoint p2) {
    final a = ((p1.y - p1.x) * (p2.y - p2.x)) % p;
    final b = ((p1.y + p1.x) * (p2.y + p2.x)) % p;
    final c = (p1.t * BigInt.two * _d * p2.t) % p;
    final d = (p1.z * BigInt.two * p2.z) % p;
    final e = (b - a) % p;
    final f = (d - c) % p;
    final g = (d + c) % p;
    final h = (b + a) % p;
    return _ExtPoint(
      (e * f) % p,
      (g * h) % p,
      (f * g) % p,
      (e * h) % p,
    );
  }

  static Uint8List encodePoint(_ExtPoint pt) {
    final zInv = pt.z.modInverse(p);
    final x = ((pt.x * zInv) % p + p) % p;
    final y = ((pt.y * zInv) % p + p) % p;
    final out = Uint8List(32);
    var tmp = y;
    for (var i = 0; i < 32; i++) {
      out[i] = (tmp & BigInt.from(0xff)).toInt();
      tmp >>= 8;
    }
    if (x.isOdd) out[31] |= 0x80;
    return out;
  }
}

class _ExtPoint {
  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;
  const _ExtPoint(this.x, this.y, this.z, this.t);
}

/// Pure-Dart 32-bit-safe SHA-512 (pairs of uint32) for Ed25519 scalar hashing.
class _PureSha512 {
  static const List<int> _kHi = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    0xca273ece, 0xd186b8c7, 0xeada7dd6, 0xf57d4f7f, 0x06f067aa, 0x0a637dc5, 0x113f9804, 0x1b710b35,
    0x28db77f5, 0x32caab7b, 0x3c9ebe0a, 0x431d67c4, 0x4cc5d4be, 0x597f299c, 0x5fcb6fab, 0x6c44198c,
  ];
  static const List<int> _kLo = [
    0xd728ae22, 0x23ef65cd, 0xec4d3b2f, 0x8189dbbc, 0xf348b538, 0xb605d019, 0xaf194f9b, 0xda6d8118,
    0xa3030242, 0x45706fbe, 0x4ee4b28c, 0xd5ffb4e2, 0xf27b896f, 0x3b1696b1, 0x25c71235, 0xcf692694,
    0x9ef14ad2, 0x384f25e3, 0x8b8cd5b5, 0x77ac9c65, 0x592b0275, 0x6ea6e483, 0xbd41fbd4, 0x831153b5,
    0xee66dfab, 0x2db43210, 0x98fb213f, 0xbeef0ee4, 0x3da88fc2, 0x930aa725, 0xe003826f, 0x0a0e6e70,
    0x46d22ffc, 0x5c26c926, 0x5ac42aed, 0x9d95b3df, 0x8baf63de, 0x3c77b2a8, 0x47edaee6, 0x1482353b,
    0x4cf10364, 0xbc423001, 0xd0f89791, 0x0654be30, 0xd6ef5218, 0x5565a910, 0x5771202a, 0x32bbd1b8,
    0xb8d2d0c8, 0x5141ab53, 0xdf8eeb99, 0xe19b48a8, 0xc5c95a63, 0xe3418acb, 0x7763e373, 0xd6b2b8a3,
    0x5defb2fc, 0x43172f60, 0xa1f0ab72, 0x1a6439ec, 0x23631e28, 0xde82bde9, 0xb2c67915, 0xe372532b,
    0xea26619c, 0x21c0c207, 0xcde0eb1e, 0xee6ed178, 0x72176fba, 0xa2c898a6, 0xbef90dae, 0x131c471b,
    0x23047d84, 0x40c72493, 0x15c9bebc, 0x9c100d4c, 0xcb3e42b6, 0xfc657e2a, 0x3ad6faec, 0x4a475817,
  ];

  static Uint8List hash(Uint8List input) {
    final bitLen = input.length * 8;
    final rem = (input.length + 17) % 128;
    final padLen = rem == 0 ? 0 : 128 - rem;
    final padded = Uint8List(input.length + 17 + padLen);
    padded.setAll(0, input);
    padded[input.length] = 0x80;
    // Write 64-bit bit length in the last 8 bytes (sufficient for < 2^53).
    final bd = ByteData.sublistView(padded);
    bd.setUint32(padded.length - 4, bitLen & 0xffffffff, Endian.big);
    bd.setUint32(padded.length - 8, (bitLen ~/ 0x100000000) & 0xffffffff, Endian.big);

    final hHi = Uint32List.fromList([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]);
    final hLo = Uint32List.fromList([
      0xf3bcc908, 0x84caa73b, 0xfe94f82b, 0x5f1d36f1,
      0xade682d1, 0x2b3e6c1f, 0xfb41bd6b, 0x137e2179,
    ]);

    final wHi = Uint32List(80);
    final wLo = Uint32List(80);

    for (var offset = 0; offset < padded.length; offset += 128) {
      for (var t = 0; t < 16; t++) {
        wHi[t] = bd.getUint32(offset + t * 8, Endian.big);
        wLo[t] = bd.getUint32(offset + t * 8 + 4, Endian.big);
      }
      for (var t = 16; t < 80; t++) {
        // s0 = rotr(1) ^ rotr(8) ^ shr(7)
        final (s0h, s0l) = _s0(wHi[t - 15], wLo[t - 15]);
        // s1 = rotr(19) ^ rotr(61) ^ shr(6)
        final (s1h, s1l) = _s1(wHi[t - 2], wLo[t - 2]);
        final (th, tl) = _add4(s1h, s1l, wHi[t - 7], wLo[t - 7], s0h, s0l,
            wHi[t - 16], wLo[t - 16]);
        wHi[t] = th;
        wLo[t] = tl;
      }

      var ah = hHi[0], al = hLo[0];
      var bh = hHi[1], bl = hLo[1];
      var ch = hHi[2], cl = hLo[2];
      var dh = hHi[3], dl = hLo[3];
      var eh = hHi[4], el = hLo[4];
      var fh = hHi[5], fl = hLo[5];
      var gh = hHi[6], gl = hLo[6];
      var hh = hHi[7], hl = hLo[7];

      for (var t = 0; t < 80; t++) {
        final (sig1h, sig1l) = _bigS1(eh, el);
        final chh = (eh & fh) ^ ((~eh) & gh);
        final chl = (el & fl) ^ ((~el) & gl);
        final (t1h, t1l) =
            _add5(hh, hl, sig1h, sig1l, chh, chl, _kHi[t], _kLo[t], wHi[t], wLo[t]);

        final (sig0h, sig0l) = _bigS0(ah, al);
        final majh = (ah & bh) ^ (ah & ch) ^ (bh & ch);
        final majl = (al & bl) ^ (al & cl) ^ (bl & cl);
        final (t2h, t2l) = _add2(sig0h, sig0l, majh, majl);

        hh = gh;
        hl = gl;
        gh = fh;
        gl = fl;
        fh = eh;
        fl = el;
        final (neh, nel) = _add2(dh, dl, t1h, t1l);
        eh = neh;
        el = nel;
        dh = ch;
        dl = cl;
        ch = bh;
        cl = bl;
        bh = ah;
        bl = al;
        final (nah, nal) = _add2(t1h, t1l, t2h, t2l);
        ah = nah;
        al = nal;
      }

      for (var i = 0; i < 8; i++) {
        final sum = switch (i) {
          0 => _add2(hHi[0], hLo[0], ah, al),
          1 => _add2(hHi[1], hLo[1], bh, bl),
          2 => _add2(hHi[2], hLo[2], ch, cl),
          3 => _add2(hHi[3], hLo[3], dh, dl),
          4 => _add2(hHi[4], hLo[4], eh, el),
          5 => _add2(hHi[5], hLo[5], fh, fl),
          6 => _add2(hHi[6], hLo[6], gh, gl),
          _ => _add2(hHi[7], hLo[7], hh, hl),
        };
        hHi[i] = sum.$1;
        hLo[i] = sum.$2;
      }
    }

    final out = Uint8List(64);
    final outBd = ByteData.sublistView(out);
    for (var i = 0; i < 8; i++) {
      outBd.setUint32(i * 8, hHi[i], Endian.big);
      outBd.setUint32(i * 8 + 4, hLo[i], Endian.big);
    }
    return out;
  }

  static (int, int) _rotr(int hi, int lo, int n) {
    if (n < 32) {
      return (
        ((hi >>> n) | (lo << (32 - n))) & 0xffffffff,
        ((lo >>> n) | (hi << (32 - n))) & 0xffffffff,
      );
    }
    final m = n - 32;
    return (
      ((lo >>> m) | (hi << (32 - m))) & 0xffffffff,
      ((hi >>> m) | (lo << (32 - m))) & 0xffffffff,
    );
  }

  static (int, int) _shr(int hi, int lo, int n) => (
        (hi >>> n) & 0xffffffff,
        ((lo >>> n) | (hi << (32 - n))) & 0xffffffff,
      );

  static (int, int) _bigS0(int hi, int lo) {
    final (h1, l1) = _rotr(hi, lo, 28);
    final (h2, l2) = _rotr(hi, lo, 34);
    final (h3, l3) = _rotr(hi, lo, 39);
    return ((h1 ^ h2 ^ h3) & 0xffffffff, (l1 ^ l2 ^ l3) & 0xffffffff);
  }

  static (int, int) _bigS1(int hi, int lo) {
    final (h1, l1) = _rotr(hi, lo, 14);
    final (h2, l2) = _rotr(hi, lo, 18);
    final (h3, l3) = _rotr(hi, lo, 41);
    return ((h1 ^ h2 ^ h3) & 0xffffffff, (l1 ^ l2 ^ l3) & 0xffffffff);
  }

  static (int, int) _s0(int hi, int lo) {
    final (h1, l1) = _rotr(hi, lo, 1);
    final (h2, l2) = _rotr(hi, lo, 8);
    final (h3, l3) = _shr(hi, lo, 7);
    return ((h1 ^ h2 ^ h3) & 0xffffffff, (l1 ^ l2 ^ l3) & 0xffffffff);
  }

  static (int, int) _s1(int hi, int lo) {
    final (h1, l1) = _rotr(hi, lo, 19);
    final (h2, l2) = _rotr(hi, lo, 61);
    final (h3, l3) = _shr(hi, lo, 6);
    return ((h1 ^ h2 ^ h3) & 0xffffffff, (l1 ^ l2 ^ l3) & 0xffffffff);
  }

  static (int, int) _add2(int h1, int l1, int h2, int l2) {
    final lo = (l1 & 0xffffffff) + (l2 & 0xffffffff);
    final hi = (h1 & 0xffffffff) + (h2 & 0xffffffff) + (lo >>> 32);
    return (hi & 0xffffffff, lo & 0xffffffff);
  }

  static (int, int) _add4(
      int h1, int l1, int h2, int l2, int h3, int l3, int h4, int l4) {
    final (ha, la) = _add2(h1, l1, h2, l2);
    final (hb, lb) = _add2(h3, l3, h4, l4);
    return _add2(ha, la, hb, lb);
  }

  static (int, int) _add5(int h1, int l1, int h2, int l2, int h3, int l3,
      int h4, int l4, int h5, int l5) {
    final (ha, la) = _add4(h1, l1, h2, l2, h3, l3, h4, l4);
    return _add2(ha, la, h5, l5);
  }
}

/// Compact pure-Dart SHA-256 for SSH key fingerprint computation (`SHA256:...`).
class _PureSha256 {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static Uint8List hash(Uint8List input) {
    final bitLen = input.length * 8;
    final rem = (input.length + 9) % 64;
    final padLen = rem == 0 ? 0 : 64 - rem;
    final padded = Uint8List(input.length + 9 + padLen);
    padded.setAll(0, input);
    padded[input.length] = 0x80;
    final bd = ByteData.sublistView(padded);
    bd.setUint32(padded.length - 4, bitLen & 0xffffffff, Endian.big);
    bd.setUint32(padded.length - 8, (bitLen ~/ 0x100000000) & 0xffffffff, Endian.big);

    final h = Uint32List.fromList([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]);
    final w = Uint32List(64);
    int r(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;

    for (var off = 0; off < padded.length; off += 64) {
      for (var t = 0; t < 16; t++) {
        w[t] = bd.getUint32(off + t * 4, Endian.big);
      }
      for (var t = 16; t < 64; t++) {
        final s0 = r(w[t - 15], 7) ^ r(w[t - 15], 18) ^ (w[t - 15] >>> 3);
        final s1 = r(w[t - 2], 17) ^ r(w[t - 2], 19) ^ (w[t - 2] >>> 10);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
      }
      var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
      for (var t = 0; t < 64; t++) {
        final s1 = r(e, 6) ^ r(e, 11) ^ r(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final t1 = (hh + s1 + ch + _k[t] + w[t]) & 0xffffffff;
        final s0 = r(a, 2) ^ r(a, 13) ^ r(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + maj) & 0xffffffff;
        hh = g;
        g = f;
        f = e;
        e = (d + t1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xffffffff;
      }
      h[0] = (h[0] + a) & 0xffffffff;
      h[1] = (h[1] + b) & 0xffffffff;
      h[2] = (h[2] + c) & 0xffffffff;
      h[3] = (h[3] + d) & 0xffffffff;
      h[4] = (h[4] + e) & 0xffffffff;
      h[5] = (h[5] + f) & 0xffffffff;
      h[6] = (h[6] + g) & 0xffffffff;
      h[7] = (h[7] + hh) & 0xffffffff;
    }

    final out = Uint8List(32);
    final outBd = ByteData.sublistView(out);
    for (var i = 0; i < 8; i++) {
      outBd.setUint32(i * 4, h[i], Endian.big);
    }
    return out;
  }
}
