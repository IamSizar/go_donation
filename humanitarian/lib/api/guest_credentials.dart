// Credentials for a guest account, generated rather than asked for.
//
// WHY THESE ARE GENERATED
// A guest is someone who wants to look around. Asking them to invent a
// username and a password first is asking for two secrets they will never
// use again — the sheet used to collect exactly that, and the client asked
// for a name and nothing else.
//
// The server still needs both: POST /auth/guest/register enforces a unique
// 3-32 handle and a 6+ character password. So the app supplies them.
//
// SECURITY NOTE
// Random.secure() is the platform CSPRNG. It matters less for the username,
// which is not a secret, than for the password — which is never shown to
// anyone, so it should be long and unguessable rather than memorable.
import 'dart:math';

/// The alphabet for generated handles. Deliberately unambiguous: no 0/O or
/// 1/l, because these end up in staff-facing tools where somebody may read
/// one aloud or copy it by eye.
const String _handleAlphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

/// A wider alphabet for the password, which is only ever machine-handled.
const String _passwordAlphabet =
    'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

final Random _rng = Random.secure();

String _pick(String alphabet, int length) => List<String>.generate(
  length,
  (_) => alphabet[_rng.nextInt(alphabet.length)],
).join();

/// A username for a new guest, e.g. `guest_k4m9xr2p`.
///
/// The `guest_` prefix is for whoever reads the users table: it says at a
/// glance what kind of account this is, without having to join anything.
///
/// 8 random characters from a 32-symbol alphabet is 40 bits — collisions are
/// not a practical concern, and [registerGuestAccount] retries anyway rather
/// than trusting that arithmetic.
String generateGuestUsername() => 'guest_${_pick(_handleAlphabet, 8)}';

/// A password for a new guest account.
///
/// 24 characters because nobody types it. The server's floor is 6; there is
/// no reason to sit anywhere near it for a value the user never sees.
String generateGuestPassword() => _pick(_passwordAlphabet, 24);
