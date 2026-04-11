import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Password hashing with PBKDF2-SHA256 for the local Flutter framework.
///
/// ODS Ethos: This is the local-only auth layer. Web frameworks will swap in
/// OpenID/Supabase. The PasswordHasher class abstracts the algorithm so it
/// can be replaced without changing callers.
///
/// Uses a pure-Dart SHA-256 implementation to avoid adding dependencies.
/// PBKDF2 with 100,000 iterations provides strong key stretching.
///
/// Hash format: "v2:salt:hash" (PBKDF2-SHA256, 100k rounds)
/// Legacy format: "salt:hash" (SHA-256, 1000 rounds) — supported for
/// backward compatibility in verify() only.
class PasswordHasher {
  static const int _pbkdf2Iterations = 100000;
  static const int _dkLen = 32; // 256-bit derived key
  static const String _v2Prefix = 'v2';

  /// Generates a random 22-character base64url salt.
  static String generateSalt() {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Url.encode(bytes);
  }

  /// Hashes a password using PBKDF2-SHA256 with 100,000 iterations.
  /// Returns a string in the format "v2:salt:hash".
  static String hash(String password, String salt) {
    final derived = _pbkdf2(password, salt, _pbkdf2Iterations, _dkLen);
    return '$_v2Prefix:$salt:${base64Url.encode(derived)}';
  }

  /// Verifies a password against a stored hash string.
  ///
  /// Supports both current (v2) and legacy formats for backward compatibility:
  ///   - "v2:salt:hash" — PBKDF2-SHA256, 100k rounds
  ///   - "salt:hash" — legacy SHA-256, 1000 rounds (will still verify)
  ///
  /// When called with (password, salt, storedHash) where storedHash does NOT
  /// contain a "v2:" prefix, falls back to legacy verification.
  static bool verify(String password, String salt, String storedHash) {
    if (storedHash.startsWith('$_v2Prefix:')) {
      // New v2 format: "v2:salt:hash" — salt and hash are embedded.
      final parts = storedHash.split(':');
      if (parts.length != 3) return false;
      final embeddedSalt = parts[1];
      final embeddedHash = parts[2];
      final derived = _pbkdf2(password, embeddedSalt, _pbkdf2Iterations, _dkLen);
      final candidateHash = base64Url.encode(derived);
      return _constantTimeEquals(candidateHash, embeddedHash);
    } else {
      // Legacy format: plain "hash" string (salt passed separately).
      final candidateHash = _legacyHash(password, salt);
      return _constantTimeEquals(candidateHash, storedHash);
    }
  }

  /// Legacy hash for backward compatibility with existing stored passwords.
  /// SHA-256 with 1000 rounds (the old algorithm).
  static String _legacyHash(String password, String salt) {
    final input = utf8.encode('$salt:$password');
    var digest = _sha256(input);
    for (int i = 0; i < 999; i++) {
      digest = _sha256([...digest, ...input]);
    }
    return base64Url.encode(digest);
  }

  /// Constant-time string comparison to prevent timing attacks.
  /// Always compares all bytes regardless of where a mismatch occurs.
  static bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) {
      // Still do a full comparison to avoid leaking length info via timing.
      int result = aBytes.length ^ bBytes.length;
      for (int i = 0; i < aBytes.length; i++) {
        result |= aBytes[i] ^ bBytes[i % bBytes.length];
      }
      return result == 0;
    }
    int result = 0;
    for (int i = 0; i < aBytes.length; i++) {
      result |= aBytes[i] ^ bBytes[i];
    }
    return result == 0;
  }

  /// PBKDF2 implementation using HMAC-SHA256.
  static List<int> _pbkdf2(String password, String salt, int iterations, int dkLen) {
    final passwordBytes = utf8.encode(password);
    final saltBytes = utf8.encode(salt);
    final numBlocks = (dkLen + 31) ~/ 32; // Each block is 32 bytes (SHA-256 output)
    final dk = <int>[];

    for (int blockIndex = 1; blockIndex <= numBlocks; blockIndex++) {
      // U1 = HMAC(password, salt || INT_32_BE(blockIndex))
      final blockBytes = [
        (blockIndex >> 24) & 0xff,
        (blockIndex >> 16) & 0xff,
        (blockIndex >> 8) & 0xff,
        blockIndex & 0xff,
      ];
      var u = hmacSha256(passwordBytes, [...saltBytes, ...blockBytes]);
      final result = List<int>.from(u);

      for (int i = 1; i < iterations; i++) {
        u = hmacSha256(passwordBytes, u);
        for (int j = 0; j < result.length; j++) {
          result[j] ^= u[j];
        }
      }
      dk.addAll(result);
    }

    return dk.sublist(0, dkLen);
  }

  /// HMAC-SHA256 implementation. Public so other modules (e.g., BackupManager)
  /// can compute message authentication codes.
  static List<int> hmacSha256(List<int> key, List<int> message) {
    const blockSize = 64;

    // Keys longer than block size are hashed first.
    var k = key.length > blockSize ? _sha256(key) : List<int>.from(key);

    // Pad key to block size.
    while (k.length < blockSize) {
      k.add(0);
    }

    final ipad = List<int>.generate(blockSize, (i) => k[i] ^ 0x36);
    final opad = List<int>.generate(blockSize, (i) => k[i] ^ 0x5c);

    final inner = _sha256([...ipad, ...message]);
    return _sha256([...opad, ...inner]);
  }

  /// Pure-Dart SHA-256 implementation.
  static List<int> _sha256(List<int> data) {
    // Initial hash values (first 32 bits of fractional parts of square roots of first 8 primes)
    final h = Uint32List.fromList([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]);

    // Round constants
    const k = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
      0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
      0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
      0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
      0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
      0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    // Pre-processing: pad message
    final bitLen = data.length * 8;
    final padded = <int>[...data, 0x80];
    while ((padded.length % 64) != 56) {
      padded.add(0);
    }
    // Append length as 64-bit big-endian
    for (int i = 56; i >= 0; i -= 8) {
      padded.add((bitLen >> i) & 0xff);
    }

    // Process each 512-bit (64-byte) block
    final w = Uint32List(64);
    for (int offset = 0; offset < padded.length; offset += 64) {
      // Prepare message schedule
      for (int i = 0; i < 16; i++) {
        w[i] = (padded[offset + i * 4] << 24) |
            (padded[offset + i * 4 + 1] << 16) |
            (padded[offset + i * 4 + 2] << 8) |
            padded[offset + i * 4 + 3];
      }
      for (int i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = _add32(w[i - 16], s0, w[i - 7], s1);
      }

      // Initialize working variables
      int a = h[0], b = h[1], c = h[2], d = h[3];
      int e = h[4], f = h[5], g = h[6], hh = h[7];

      // Compression
      for (int i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
        final temp1 = _add32(hh, s1, ch, k[i], w[i]);
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xFFFFFFFF;

        hh = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      h[0] = (h[0] + a) & 0xFFFFFFFF;
      h[1] = (h[1] + b) & 0xFFFFFFFF;
      h[2] = (h[2] + c) & 0xFFFFFFFF;
      h[3] = (h[3] + d) & 0xFFFFFFFF;
      h[4] = (h[4] + e) & 0xFFFFFFFF;
      h[5] = (h[5] + f) & 0xFFFFFFFF;
      h[6] = (h[6] + g) & 0xFFFFFFFF;
      h[7] = (h[7] + hh) & 0xFFFFFFFF;
    }

    // Produce the final hash value (big-endian)
    final result = <int>[];
    for (int i = 0; i < 8; i++) {
      result.add((h[i] >> 24) & 0xff);
      result.add((h[i] >> 16) & 0xff);
      result.add((h[i] >> 8) & 0xff);
      result.add(h[i] & 0xff);
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Password validation (shared utility, matching React version)
  // -------------------------------------------------------------------------

  /// Validate a password against requirements.
  /// Returns null if valid, or an error message string.
  static String? validatePassword(String password) {
    if (password.length < 8) return 'Password must be at least 8 characters.';
    if (password.length > 72) return 'Password must be 72 characters or fewer.';
    return null;
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

  static int _add32(int a, int b, [int c = 0, int d = 0, int e = 0]) {
    return (a + b + c + d + e) & 0xFFFFFFFF;
  }
}
