// Names the sender of a 1:1 chat message in the reader's language —
// OPOS #26435.
//
// WHY THIS FILE EXISTS
// The server sends a message's `sender_name` as the sender's profile name, and
// sends null when there is none to show: a staff account with no profile name,
// or a sender whose privacy settings hide it from this viewer
// (backend/internal/privacy Viewer.Name deliberately leaves that placeholder to
// the client). ChatMessage.fromMap used to fill the gap with the English words
// "Support" and "User", so an Arabic user read English above a support reply.
//
// The model now keeps only what the server sent, and the gap is filled here,
// when the bubble is built, in whatever language is current at that moment.
//
// WHICH WORDS — both are existing keys, so nothing new needs translating:
//   * A staff reply reuses `chat_group_sender_support` ("Support" / فريق الدعم),
//     the words the chat groups already sign every staff message with
//     (OPOS #26419). One support team, one name in both kinds of chat. A bare
//     الدعم would be wrong: it already means Kafala, and TERMINOLOGY.md T10
//     settles that the two must differ.
//   * Any other sender reuses `User` ("User" / مستخدم).
//
// A key missing from the current language resolves through the app's English
// fallbackLocale (main.dart), so a key name is never drawn.
import 'package:get/get.dart';

import '../models/chat_models.dart';

// ─── Translation keys ───

/// Signs a staff reply that carries no name. Shared with the chat groups.
const _supportKey = 'chat_group_sender_support';

/// Names any other sender that carries no name.
const _userKey = 'User';

// ─── Resolution ───

/// The name to draw above [message], in the current language.
///
/// Returns the server's name unchanged whenever there is one, in every
/// language. Otherwise returns the support team's name for a staff reply
/// ([ChatMessage.isSupport]) and a generic "User" for anyone else, translated.
String chatSenderName(ChatMessage message) {
  if (message.senderName.isNotEmpty) return message.senderName;
  return (message.isSupport ? _supportKey : _userKey).tr;
}
