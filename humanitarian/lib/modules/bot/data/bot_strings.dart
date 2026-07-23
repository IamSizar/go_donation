/// Self-contained localization for the AI Support Assistant's static UI strings
/// (header, welcome bubble, input hint, offline error). Kept inside the bot
/// module — like the BotQA tables — so the feature is fully multilingual without
/// depending on global locale-file keys.
///
/// Lookup falls back to English for any missing language, and returns the key
/// itself if the key is unknown (so a typo is visible rather than silent).
abstract final class BotStrings {
  static const Map<String, Map<String, String>> _data = {
    'title': {
      'en': 'Support Assistant',
      'ar': 'مساعد الدعم',
      'ckb': 'یاریدەدەری پشتگیری',
      'kmr': 'هاریکارێ پشتگیری',
    },
    'subtitle': {
      'en': 'AI-powered · always here to help',
      'ar': 'مدعوم بالذكاء الاصطناعي · دائماً هنا للمساعدة',
      'ckb': 'پاڵپشتیکراو بە AI · هەمیشە لێرەیە بۆ یارمەتی',
      'kmr': 'ب AI ڤە · هەمیشە ل ڤێرە بۆ هاریکاریێ',
    },
    'welcome': {
      'en': 'Hi there! 👋  I\'m your Support Assistant.\n'
          'Ask me anything about the app — how to donate, track a request, '
          'chat with someone, and more. Tap a suggestion below or type your '
          'own question.',
      'ar': 'مرحباً! 👋  أنا مساعد الدعم الخاص بك.\n'
          'اسألني أي شيء عن التطبيق — كيفية التبرع، تتبع طلب، التواصل مع شخص ما، '
          'والمزيد. اضغط على اقتراح أدناه أو اكتب سؤالك.',
      'ckb': 'سڵاو! 👋  من یاریدەدەری پشتگیریتم.\n'
          'هەر شتێکم لێ بپرسە دەربارەی ئەپەکە — چۆن بەخشین بکەیت، داواکارییەک '
          'بشوێنیتەوە، لەگەڵ کەسێک گفتوگۆ بکەیت، و زیاتر. پێشنیارێکی خوارەوە بپەڕە '
          'یان پرسیارەکەت بنووسە.',
      'kmr': 'سلاڤ! 👋  ئەز هاریکارێ پشتگیریا تەمە.\n'
          'هەر تشتەکی دەربارەی ئەپی ژ من بپرسە — چەوا ببەخشم، داخوازەکێ '
          'بشوپینم، دگەل کەسەکی ئاخفتنێ بکەم، و پتر. پێشنیارەکێ ل خوارێ '
          'کلیک بکە یان پرسیارا خۆ بنڤیسە.',
    },
    'suggestionsHeader': {
      'en': 'How can I help you?',
      'ar': 'كيف يمكنني مساعدتك؟',
      'ckb': 'چۆن دەتوانم یارمەتیت بدەم؟',
      'kmr': 'ئەز چەوا دشێم هاریکاریا تە بکەم؟',
    },
    'tapHint': {
      'en': 'Tap a question above to ask',
      'ar': 'اضغط على سؤال بالأعلى للسؤال',
      'ckb': 'لەسەر پرسیارێک لە سەرەوە بپەڕە بۆ پرسیارکردن',
      'kmr': 'ل سەر پرسیارەکێ ل سەرێ بتکینە بۆ پرسینێ',
    },
    'inputHint': {
      'en': 'Type your question…',
      'ar': 'اكتب سؤالك…',
      'ckb': 'پرسیارەکەت بنووسە…',
      'kmr': 'پرسیارا خۆ بنڤیسە…',
    },
    'error': {
      'en': 'I\'m having trouble reaching the assistant right now. Please check '
          'your connection and try again, or contact our support team from the '
          'Services section.',
      'ar': 'أواجه مشكلة في الوصول إلى المساعد الآن. يرجى التحقق من اتصالك '
          'والمحاولة مرة أخرى، أو التواصل مع فريق الدعم من قسم الخدمات.',
      'ckb': 'ئێستا کێشەم هەیە لە گەیشتن بە یاریدەدەرەکە. تکایە پەیوەندیەکەت بپشکنە '
          'و دووبارە هەوڵبدەوە، یان پەیوەندی بە تیمی پشتگیریمانەوە بکە لە بەشی '
          'خزمەتگوزارییەکان.',
      'kmr': 'نوکە کێشە هەیە د گەهشتنا هاریکاری دا. ژ کەرەما خۆ پەیوەندیا خۆ '
          'ببینە و دیسا هەول بدە، یان پەیوەندیێ دگەل تیمێ پشتگیریا مە ژ '
          'بەشا خزمەتگوزاریان بکە.',
    },
  };

  /// Returns the [key] string for [lang], falling back to English, then [key].
  static String of(String key, String lang) {
    final byLang = _data[key];
    if (byLang == null) return key;
    return byLang[lang] ?? byLang['en'] ?? key;
  }
}
