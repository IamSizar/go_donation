import 'package:flutter/material.dart';

import '../models/bot_qa.dart';

/// Returns the FAQ list tailored to the given [roleId].
///
/// role '1' = Contributor  |  '2' = Recipient  |  '3' = Volunteer
/// Falls back to donor questions for any other value.
///
/// `actionRoute` values are route keys resolved by BotNavigation, so a chip tap
/// (offline path) navigates to the SAME concrete screen the AI would route to.
///
/// Each entry carries `questionsByLang` / `answersByLang` / `keywordsByLang` so
/// the chips, the user bubble, and the OFFLINE fallback answer + keyword
/// matching all work in the app's current locale (ar / ckb / kmr), falling back
/// to the English fields. These mirror the backend assistant intent tables, so
/// the offline experience matches the online (AI / keyword-engine) experience.
///
/// Language note: `ckb` is Kurdish Sorani (Central Kurdish) and `kmr` is Kurdish
/// Behdini/Badini written in the ARABIC script (not Latin Kurmanji) — matching
/// the app's existing `_badini` translations.
List<BotQA> getBotQAs(String roleId) {
  switch (roleId) {
    case '2':
      return beneficiaryQAs;
    case '3':
      return volunteerQAs;
    default:
      return donorQAs;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABOUT THE APP — shared "what is this app / how it works" questions appended
// to every role's list so users can learn what the platform does.
// ─────────────────────────────────────────────────────────────────────────────

const List<BotQA> _aboutAppQAs = [
  BotQA(
    id: 'about_app',
    icon: Icons.info_rounded,
    question: 'What is this app and what does it do?',
    questionsByLang: {
      'ar': 'ما هو هذا التطبيق وماذا يفعل؟',
      'ckb': 'ئەم ئەپە چییە و چی دەکات؟',
      'kmr': 'ئەڤ ئەپە چییە و چ دکەت؟',
    },
    answer:
        'This is a humanitarian aid platform that connects donors, '
        'beneficiaries and volunteers. You can donate to campaigns, sponsor '
        'families through Kafala, request or receive aid, buy and sell in the '
        'beneficiary marketplace, join volunteer missions, and reach community '
        'services — all in one place.',
    answersByLang: {
      'ar': 'هذه منصة إغاثة إنسانية تربط المتبرعين والمستفيدين والمتطوعين. يمكنك التبرع للحملات، كفالة أسر عبر الكفالة، طلب أو تلقي المساعدة، البيع والشراء في سوق المستفيدين، الانضمام لمهام التطوع، والوصول إلى خدمات المجتمع — كل ذلك في مكان واحد.',
      'ckb': 'ئەمە سەکۆیەکی یارمەتی مرۆییە کە بەخشەر، سوودمەند و خۆبەخشان بەیەکەوە دەبەستێتەوە. دەتوانیت بەخشین بۆ کامپەینەکان بکەیت، خێزان لەڕێی کەفالەوە پاڵپشتی بکەیت، داوای یارمەتی بکەیت یان وەریبگریت، لە بازاڕی سوودمەنداندا بکڕیت و بفرۆشیت، بەشداری ئەرکی خۆبەخشی بکەیت، و دەستت بگات بە خزمەتگوزاریی کۆمەڵگا — هەمووی لە یەک شوێندا.',
      'kmr': 'ئەڤ پلاتفۆرمەکا یارمەتیا مرۆڤایەتییە یا کو بەخشەر، سوودمەند و خۆبەخشان بەیەکڤە گرێ ددەت. تو دشێی بۆ کامپینان ببەخشی، خێزانان ب کەفالە پاڵپشتی بکەی، داخوازا یارمەتیێ بکەی یان وەربگری، ل بازارا سوودمەندان بکڕی و بفرۆشی، بەشداری ئەرکێن خۆبەخشیێ بکەی، و گەهشتنا خزمەتگوزاریێن جڤاکی بکەی — هەمی ل یەک جهی.',
    },
    keywords: ['about', 'what is this app', 'what app', 'platform', 'purpose', 'what does this app'],
    keywordsByLang: {
      'ar': ['ما هو التطبيق', 'عن التطبيق', 'ما هذا', 'المنصة'],
      'ckb': ['دەربارەی ئەپ', 'ئەپ چییە', 'ئەمە چییە', 'سەکۆ'],
      'kmr': ['دەربارەی ئەپی', 'ئەپ چییە', 'ئەڤ چییە', 'پلاتفۆرم'],
    },
    actionLabel: 'Explore Services',
    actionRoute: 'services',
  ),
  BotQA(
    id: 'about_how',
    icon: Icons.lightbulb_rounded,
    question: 'How does the app work?',
    questionsByLang: {
      'ar': 'كيف يعمل التطبيق؟',
      'ckb': 'ئەپەکە چۆن کار دەکات؟',
      'kmr': 'ئەپ چەوا کار دکەت؟',
    },
    answer:
        'Pick what you need from the tabs: Home shows highlights and quick '
        'actions; Contribute and Kafala for giving and support; Market for '
        'products; Services for forms like marriage support and beneficiary '
        'cases; Alerts for updates; and Messages to chat. The admin team '
        'reviews requests and you are notified at every step.',
    answersByLang: {
      'ar': 'اختر ما تحتاجه من التبويبات: الرئيسية تعرض أهم الأمور والإجراءات السريعة؛ التبرع والكفالة للعطاء والكفالات؛ السوق للمنتجات؛ الخدمات للنماذج مثل دعم الزواج وحالات المستفيدين؛ التنبيهات للتحديثات؛ والرسائل للمحادثة. يراجع فريق الإدارة الطلبات وتصلك إشعارات في كل خطوة.',
      'ckb': 'ئەوەی پێویستتە لە تابەکان هەڵبژێرە: سەرەتا گرنگترین شتەکان و کردارە خێراکان پیشان دەدات؛ بەخشین و کەفالە بۆ بەخشین و کەفالەکان؛ بازاڕ بۆ بەرهەمەکان؛ خزمەتگوزارییەکان بۆ فۆرمەکان وەک پشتگیری زەواج و کەیسی سوودمەندان؛ ئاگادارکردنەوەکان بۆ نوێکارییەکان؛ و پەیامەکان بۆ گفتوگۆ. تیمی بەڕێوەبردن داواکارییەکان پشکنینەوە دەکات و لە هەر هەنگاوێکدا ئاگادار دەکرێیتەوە.',
      'kmr': 'ئەوا پێدڤیی تە یە ژ تابان هەلبژێرە: سەرەکی گرنگترین تشتان و کارێن لەز نیشان ددەت؛ بەخشین و کەفالە بۆ بەخشین و کەفالان؛ بازار بۆ بەرهەمان؛ خزمەتگوزاری بۆ فۆرمان وەک پشتگیریا زەواجێ و کەیسێن سوودمەندان؛ ئاگەهداری بۆ نویکاریان؛ و پەیام بۆ ئاخفتنێ. تیمێ بەڕێڤەبرینێ داخوازان ددەتە بەر چاڤان و تو د هەر گاڤەکێ دا ئاگەهدار دبی.',
    },
    keywords: ['how it works', 'how does', 'how to use', 'navigate', 'guide me'],
    keywordsByLang: {
      'ar': ['كيف يعمل', 'طريقة العمل', 'كيف أستخدم'],
      'ckb': ['چۆن کار دەکات', 'چۆن بەکاربهێنم', 'ڕێنمایی'],
      'kmr': ['چەوا کار دکەت', 'چەوا بکاربینم', 'رێبەری'],
    },
    actionLabel: 'Explore Services',
    actionRoute: 'services',
  ),
  BotQA(
    id: 'about_start',
    icon: Icons.rocket_launch_rounded,
    question: 'How do I get started?',
    questionsByLang: {
      'ar': 'كيف أبدأ؟',
      'ckb': 'چۆن دەست پێ بکەم؟',
      'kmr': 'ئەز چەوا دەست پێ بکەم؟',
    },
    answer:
        'Start by completing your profile so your account looks trusted. Then '
        'explore the tabs that match your role — donate or sponsor, submit a '
        'request, or join a mission. Tap any suggested question here and I will '
        'take you straight to the right screen.',
    answersByLang: {
      'ar': 'ابدأ بإكمال ملفك الشخصي ليبدو حسابك موثوقاً. ثم استكشف التبويبات المناسبة لدورك — تبرّع أو اكفل، قدّم طلباً، أو انضم لمهمة. اضغط أي سؤال مقترح هنا وسآخذك مباشرة إلى الشاشة الصحيحة.',
      'ckb': 'بە تەواوکردنی پرۆفایلەکەت دەست پێ بکە تا هەژمارەکەت متمانەپێکراو دیار بێت. ئینجا ئەو تابانە بگەڕێ کە لەگەڵ ڕۆڵەکەتدا دەگونجێن — بەخشین بکە یان کەفالە، داواکارییەک پێشکەش بکە، یان بەشداری ئەرکێک بکە. هەر پرسیارێکی پێشنیارکراو لێرە بپەڕە و ڕاستەوخۆ دەتبەمە شاشە دروستەکە.',
      'kmr': 'ب تەمامکرنا پرۆفایلا خۆ دەست پێ بکە دا حسابێ تە باوەرپێکری دیار بیت. پاشی وان تابان بگەڕە یێن کو دگەل ڕۆلا تە دگونجن — ببەخشە یان کەفالە بکە، داخوازەکێ پێشکێش بکە، یان بەشداری ئەرکەکێ بکە. هەر پرسیارەکا پێشنیارکری ل ڤێرە بتکینە و ئەز دێ رەستەوخۆ تە بەمە شاشا دروست.',
    },
    keywords: ['get started', 'getting started', 'begin', 'new here', 'first time', 'start'],
    keywordsByLang: {
      'ar': ['كيف أبدأ', 'البداية', 'أنا جديد'],
      'ckb': ['چۆن دەست پێ بکەم', 'دەستپێک', 'نوێم'],
      'kmr': ['چەوا دەست پێ بکەم', 'دەستپێک', 'ئەز نوی مە'],
    },
    actionLabel: 'Edit Profile',
    actionRoute: 'edit_profile',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// DONOR  (role 1)
// ─────────────────────────────────────────────────────────────────────────────

const List<BotQA> donorQAs = [
  BotQA(
    id: 'd_donate',
    icon: Icons.volunteer_activism_rounded,
    question: 'How do I donate to a campaign?',
    questionsByLang: {
      'ar': 'كيف أتبرع لحملة؟',
      'ckb': 'چۆن بۆ کامپەینێک بەخشین بکەم؟',
      'kmr': 'ئەز چەوا بۆ کامپینەکێ ببەخشم؟',
    },
    answer:
        'Open the Contribute section and browse active campaigns. Tap a campaign to '
        'view its goal and progress, then tap "Contribute", enter your amount, '
        'review the summary and confirm. You\'ll be notified when your donation '
        'is received and again once an admin approves it.',
    answersByLang: {
      'ar': 'لتتبرع، افتح تبويب التبرع وتصفح الحملات النشطة. اضغط على أي حملة لرؤية هدفها وتقدمها، ثم اضغط على "تبرع"، أدخل المبلغ، راجع الملخص وأكّد. ستتلقى إشعاراً عند استلام تبرعك وآخر عند موافقة المشرف.',
      'ckb': 'بۆ بەخشین، تابی بەخشین بکەوە و کامپەینە چالاکەکان ببینە. لەسەر هەر کامپەینێک بپەڕە بۆ دیتنی ئامانج و پێشکەوتنی، ئەوکات "بەخشین" بپەڕە، بڕ بنووسە، پوختەکە بپشکنە و پشتگیری بکە. ئاگادارت دەکرێیتەوە کاتێک بەخشینەکەت وەرگیراوە و دیسان کاتێک بەرپرسی پەسەندکردنەکە موافەقەتی دەکات.',
      'kmr': 'بۆ بەخشینێ، تابا بەخشینێ ڤەکە و ل کامپینێن چالاک بگەڕە. ل کامپینەکێ کلیک بکە دا ئامانج و پێشکەفتنا وێ ببینی، پاشی "بەخشین" کلیک بکە، بڕی پارەی بنڤیسە، کورتییێ ببینە و پشتراست بکە. دێ ئاگەهدار بی دەمێ بەخشینا تە دگەهیتە و دیسا دەمێ بەڕێڤەبەری پەسەند کری.',
    },
    keywords: ['donat', 'campaign', 'give', 'contribut', 'fund', 'how to donat'],
    keywordsByLang: {
      'ar': ['تبرع', 'كيف أتبرع', 'حملة', 'مساهمة', 'تمويل', 'منح'],
      'ckb': ['بەخشین', 'چۆن بەخشیم', 'کامپەین', 'مەبەست', 'داری بدەم'],
      'kmr': ['بەخشین', 'ئەز چەوا ببەخشم', 'کامپین', 'بەشداری', 'پارە'],
    },
    actionLabel: 'Go to Campaigns',
    actionRoute: 'donate',
  ),
  BotQA(
    id: 'd_history',
    icon: Icons.history_rounded,
    question: 'How do I view my donation history?',
    questionsByLang: {
      'ar': 'كيف أعرض سجل تبرعاتي؟',
      'ckb': 'چۆن مێژووی بەخشینەکانم ببینم؟',
      'kmr': 'ئەز چەوا مێژووا بەخشینێن خۆ ببینم؟',
    },
    answer:
        'Your contribution history opens in My Contributions. Tap "View Details" on any '
        'item to see its status, amount, and whether it has been approved, '
        'received or delivered.',
    answersByLang: {
      'ar': 'سجل تبرعاتك موجود في تبويب التبرع — مرر للأسفل للوصول إلى قائمتك الشخصية. اضغط على "عرض التفاصيل" لأي بند لرؤية المبلغ وما إذا تمت الموافقة عليه أو استلامه أو تسليمه.',
      'ckb': 'مێژووی بەخشینەکانت لە تابی بەخشین دایە — بخلیزە خوارەوە بۆ لیستی کەسیت. لەسەر "بینینی وردەکاری" بپەڕە بۆ هەر بابەتێک بۆ دیتنی بڕ و ئەوەی ئایا پەسەند کراوە، وەرگیراوە، یان گەیاندراوە.',
      'kmr': 'مێژووا بەخشینێن تە د تابا بەخشینێ دایە — بۆ خوارێ بکێشە بۆ لیستا خۆ. ل "دیتنا وردەکاری" بۆ هەر تشتەکێ کلیک بکە دا بڕی و کا هاتیە پەسەندکرن، وەرگرتن یان گەهاندن ببینی.',
    },
    keywords: ['history', 'past', 'my donation', 'previous', 'track', 'status', 'record'],
    keywordsByLang: {
      'ar': ['تاريخ التبرعات', 'تبرعاتي', 'سجل', 'تتبع', 'حالة التبرع', 'السابق'],
      'ckb': ['مێژووی بەخشین', 'بەخشینەکانم', 'تاریخچەکە', 'شوێنکردنەوە'],
      'kmr': ['مێژووا بەخشینان', 'بەخشینێن من', 'دۆخ', 'شوپاندن'],
    },
    actionLabel: 'View My Contributions',
    actionRoute: 'my_donations',
  ),
  BotQA(
    id: 'd_chat_owner',
    icon: Icons.chat_bubble_rounded,
    question: 'How do I chat with a campaign owner?',
    questionsByLang: {
      'ar': 'كيف أتحدث مع صاحب الحملة؟',
      'ckb': 'چۆن لەگەڵ خاوەنی کامپەین گفتوگۆ بکەم؟',
      'kmr': 'ئەز چەوا دگەل خودانێ کامپینێ ئاخفتنێ بکەم؟',
    },
    answer:
        'After donating, open My Contributions and tap "View Details" on that '
        'donation — you\'ll see a "Chat with campaign owner" button. The owner '
        'is notified and can accept; once accepted, you, the owner and our '
        'support team can message privately.',
    answersByLang: {
      'ar': 'بعد التبرع لحملة، افتح تبرعاتي واضغط على "عرض التفاصيل" لذلك التبرع، ثم "محادثة مع صاحب الحملة" وأكّد. سيتلقى صاحب الحملة إشعاراً ويمكنه القبول — بمجرد القبول، يمكنكم أنتم وصاحب الحملة وفريق الدعم التراسل بشكل خاص.',
      'ckb': 'پاش بەخشین بۆ کامپەینێک، بەخشینەکانم بکەوە و "بینینی وردەکاری" بپەڕە لەسەر ئەو بەخشینەکە، ئەوکات "گفتوگۆ لەگەڵ خاوەنی کامپەین" بپەڕە و پشتگیری بکە. خاوەنەکە ئاگادار دەکرێیتەوە و دەتوانێت قبووڵ بکات — کاتێک قبووڵ کرا، تۆ، خاوەنەکە و تیمی پشتگیریمان دەتوانن بە تایبەتی پەیامبنێرن.',
      'kmr': 'پشتی بەخشینێ، بەخشینێن خۆ ڤەکە و ل "دیتنا وردەکاری" بۆ وێ بەخشینێ کلیک بکە، پاشی ل "ئاخفتن دگەل خودانێ کامپینێ" کلیک بکە و پشتراست بکە. خودان دێ ئاگەهدار بیت و دشێت پەسەند بکەت — دەمێ پەسەندکر، تو، خودان و تیمێ پشتگیریا مە دشێن ب تایبەتی پەیاما بشینن.',
    },
    keywords: ['chat', 'owner', 'contact', 'message', 'talk', 'communicate', 'reach'],
    keywordsByLang: {
      'ar': ['محادثة', 'صاحب الحملة', 'تواصل', 'رسالة', 'كلام', 'تحدث'],
      'ckb': ['گفتوگۆ', 'خاوەنی کامپەین', 'پەیام', 'پەیوەندی'],
      'kmr': ['ئاخفتن', 'خودانێ کامپینێ', 'پەیام', 'پەیوەندی'],
    },
    actionLabel: 'View My Contributions',
    actionRoute: 'my_donations',
  ),
  BotQA(
    id: 'd_market',
    icon: Icons.storefront_rounded,
    question: 'How do I buy from the marketplace?',
    questionsByLang: {
      'ar': 'كيف أشتري من السوق؟',
      'ckb': 'چۆن لە بازاڕ بکڕم؟',
      'kmr': 'ئەز چەوا ژ بازارێ بکڕم؟',
    },
    answer:
        'Open the Market tab to browse handmade and local products sold by '
        'beneficiaries. Tap a product to view photos and the price, then place '
        'your order — every purchase directly supports the seller.',
    answersByLang: {
      'ar': 'افتح تبويب السوق لتصفح المنتجات اليدوية والمحلية التي يبيعها المستفيدون. اضغط على أي منتج للاطلاع على الصور والسعر، ثم ضع طلبك — كل عملية شراء تدعم البائع مباشرة.',
      'ckb': 'تابی بازاڕ بکەوە بۆ گەڕان لە بەرهەمە دەستکردەکان و شوێنییەکانی فرۆشراو لەلایەن سوودمەنداکانەوە. لەسەر بەرهەمێک بپەڕە بۆ وێنەکان و نرخ، ئەوکات داواکارییەکەت بنێرە — هەر کڕینێک ڕاستەوخۆ پشتگیری فرۆشەندەکە دەکات.',
      'kmr': 'تابا بازارێ ڤەکە دا بەرهەمێن دەستکرن و خۆجهی یێن کو ژ لایێ سوودمەندان ڤە تێنە فرۆتن ببینی. ل بەرهەمەکێ کلیک بکە بۆ وێنە و بها، پاشی داخوازا خۆ بنێرە — هەر کڕینەک رەستەوخۆ پشتگیریا فرۆشیاری دکەت.',
    },
    keywords: ['market', 'buy', 'shop', 'product', 'order', 'purchase', 'marketplace'],
    keywordsByLang: {
      'ar': ['سوق', 'شراء', 'منتج', 'تسوق', 'طلب', 'بازار'],
      'ckb': ['بازاڕ', 'کڕین', 'بەرهەم', 'مەحسووڵ'],
      'kmr': ['بازار', 'کڕین', 'بەرهەم', 'فرۆشگەه'],
    },
    actionLabel: 'Open Market',
    actionRoute: 'market',
  ),
  BotQA(
    id: 'd_marriage',
    icon: Icons.favorite_rounded,
    question: 'How do I request a marriage support service?',
    questionsByLang: {
      'ar': 'كيف أطلب خدمة دعم الزواج؟',
      'ckb': 'چۆن داوای خزمەتگوزاری پشتگیری زەواج بکەم؟',
      'kmr': 'ئەز چەوا داخوازا خزمەتا پشتگیریا هاوسەرگیریێ بکەم؟',
    },
    answer:
        'Marriage support has a dedicated form. Tap below to open it, fill in '
        'your details and submit — our team reviews every request and contacts '
        'you directly.',
    answersByLang: {
      'ar': 'يتم التعامل مع طلبات دعم الزواج من خلال نموذج مخصص. اضغط أدناه لفتحه، أدخل تفاصيلك وأرسله — فريقنا يراجع كل طلب ويتواصل معك مباشرة.',
      'ckb': 'داواکاریە پشتگیری زەواجیەکان لەڕێی فۆرمی تایبەتدا بەڕێوەدەچن. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی، وردەکارییەکانت بنووسە و بینێرە — تیمەکەمان هەموو داواکارییەکی پشکنینەوە دەکات و ڕاستەوخۆ پەیوەندیت پێوە دەکات.',
      'kmr': 'داخوازێن پشتگیریا هاوسەرگیریێ ب فۆرمەکا تایبەت تێنە بەڕێڤەبرن. ل خوارێ کلیک بکە دا ڤەکەی، وردەکاریێن خۆ بنڤیسە و بنێرە — تیمێ مە هەر داخوازەکێ ددەتە بەر چاڤان و رەستەوخۆ دگەل تە پەیوەندیێ دکەت.',
    },
    keywords: ['marriage', 'marry', 'wedding', 'nikah', 'zawaj'],
    keywordsByLang: {
      'ar': ['زواج', 'نكاح', 'عقد زواج', 'دعم زواج', 'زواج إسلامي'],
      'ckb': ['زەواج', 'خەنابەستن', 'پشتگیری زەواج', 'نیکاح'],
      'kmr': ['هاوسەرگیری', 'نکاح', 'پشتگیریا هاوسەرگیریێ'],
    },
    actionLabel: 'Open Marriage Form',
    actionRoute: 'marriage',
  ),
  BotQA(
    id: 'd_kafala',
    icon: Icons.diversity_1_rounded,
    question: 'What is Kafala sponsorship and how does it work?',
    questionsByLang: {
      'ar': 'ما هي كفالة الرعاية وكيف تعمل؟',
      'ckb': 'کەفالە چییە و چۆن کار دەکات؟',
      'kmr': 'کەفالە چییە و چەوا کار دکەت؟',
    },
    answer:
        'Kafala is our sponsorship programme that connects donors with families '
        'who need ongoing support. Browse beneficiary profiles, read their '
        'stories and contribute regularly for a lasting impact.',
    answersByLang: {
      'ar': 'الكفالة هي برنامج الرعاية لدينا الذي يربط المتبرعين بالأسر المحتاجة لدعم مستمر. يمكنك تصفح ملفات المستفيدين وقراءة قصصهم والمساهمة بانتظام — تأثير دائم لأسرة بعينها.',
      'ckb': 'کەفالە بەرنامەی پاڵپشتییمانە کە بەخشەران بە خێزانانی پێویستمەند بە پشتگیری بەردەوام دەبەستێتەوە. دەتوانیت پرۆفایلی سوودمەنداکان ببینیت، چیرۆکەکانیان بخوێنیتەوە و بە ریتم بەشداری بکەیت — کاریگەرییەکی مەزن بۆ خێزانێکی دیاریکراو.',
      'kmr': 'کەفالە بەرنامەیا پشتگیریا مەیە یا کو بەخشەران دگەل خێزانێن پێدڤی ب پشتگیریا بەردەوام گرێ ددەت. تو دشێی پرۆفایلێن سوودمەندان ببینی، چیرۆکێن وان بخوینی و ب رێکوپێک بەشداری بکەی — کاریگەرییەکا مایندە بۆ خێزانەکا دیاریکری.',
    },
    keywords: ['kafala', 'sponsor', 'sponsorship', 'family', 'adopt', 'ongoing', 'monthly'],
    keywordsByLang: {
      'ar': ['كفالة', 'رعاية', 'كفيل', 'أسرة', 'كفالة أسرة', 'راتب شهري'],
      'ckb': ['کەفالە', 'پاڵپشتی', 'خێزان', 'پاڵپشتی مانگانە'],
      'kmr': ['کەفالە', 'پشتگیری', 'خێزان', 'پشتگیریا مانگانە'],
    },
    actionLabel: 'Open Kafala',
    actionRoute: 'kafala',
  ),
  BotQA(
    id: 'd_notifications',
    icon: Icons.notifications_active_rounded,
    question: 'How do I check my notifications and alerts?',
    questionsByLang: {
      'ar': 'كيف أتحقق من إشعاراتي وتنبيهاتي؟',
      'ckb': 'چۆن ئاگادارکردنەوەکانم بپشکنم؟',
      'kmr': 'ئەز چەوا ئاگەهداریێن خۆ ببینم؟',
    },
    answer:
        'Tap the Alerts tab to see all your notifications — donation status '
        'updates, chat requests, campaign news and more. Swipe any notification '
        'to mark it read.',
    answersByLang: {
      'ar': 'اضغط على تبويب التنبيهات لرؤية جميع إشعاراتك — تحديثات حالة التبرع وطلبات المحادثة وأخبار الحملات والمزيد. مرر أي إشعار لتحديد حالته كمقروء.',
      'ckb': 'تابی ئاگادارکردنەوەکان بپەڕە بۆ دیتنی هەموو ئاگادارکردنەوەکانت — نوێکردنەوەی حاڵەتی بەخشین، داواکاریە گفتوگۆیەکان، هەواڵی کامپەین و زیاتر. هەر ئاگادارکردنەوەیەک بخلیزە بۆ نیشانەکردنی وەک خوێندراوەوە.',
      'kmr': 'تابا ئاگەهداریان کلیک بکە دا هەمی ئاگەهداریێن خۆ ببینی — نویکرنا دۆخێ بەخشینێ، داخوازێن ئاخفتنێ، نووچەیێن کامپینێ و پتر. هەر ئاگەهداریەکێ بخلیزینە دا وەک خواندی نیشان بدەی.',
    },
    keywords: ['notif', 'alert', 'news', 'update', 'bell', 'inform'],
    keywordsByLang: {
      'ar': ['إشعارات', 'تنبيهات', 'أخبار', 'تحديثات', 'الجرس'],
      'ckb': ['ئاگادارکردنەوە', 'تنبیه', 'هەواڵ', 'نوێکردنەوە'],
      'kmr': ['ئاگەهداری', 'هشیاری', 'نووچە', 'نویکرن'],
    },
    actionLabel: 'Go to Alerts',
    actionRoute: 'alerts',
  ),
  BotQA(
    id: 'd_profile',
    icon: Icons.person_rounded,
    question: 'How do I edit my profile?',
    questionsByLang: {
      'ar': 'كيف أعدّل ملفي الشخصي؟',
      'ckb': 'چۆن پرۆفایلەکەم دەستکاری بکەم؟',
      'kmr': 'ئەز چەوا پرۆفایلا خۆ دەستکاری بکەم؟',
    },
    answer:
        'You can update your name, photo and personal details on the Edit '
        'Profile screen. Tap below to open it — changes save immediately.',
    answersByLang: {
      'ar': 'يمكنك تحديث اسمك وصورتك وبياناتك الشخصية في شاشة تعديل الملف الشخصي. اضغط أدناه لفتحها — تُحفظ التغييرات فوراً.',
      'ckb': 'دەتوانیت ناوت، وێنەت و وردەکارییە کەسییەکانت لە شاشەی دەستکاریکردنی پرۆفایل نوێ بکەیتەوە. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی — گۆڕانکارییەکان ڕاستەوخۆ پاشکەوت دەکرێن.',
      'kmr': 'تو دشێی ناڤێ خۆ، وێنەیێ خۆ و وردەکاریێن کەسی ل سەر سکرینا دەستکاریا پرۆفایلێ نویکەی. ل خوارێ کلیک بکە دا ڤەکەی — گهۆرین رەستەوخۆ تێنە تۆمارکرن.',
    },
    keywords: ['profile', 'edit', 'update', 'name', 'photo', 'picture', 'account', 'setting'],
    keywordsByLang: {
      'ar': ['ملف شخصي', 'تعديل', 'اسم', 'صورة', 'الحساب', 'الإعدادات'],
      'ckb': ['پرۆفایل', 'دەستکاریکردن', 'ناو', 'وێنە', 'ژمارەکە'],
      'kmr': ['پرۆفایل', 'دەستکاری', 'ناڤ', 'وێنە', 'حساب'],
    },
    actionLabel: 'Edit Profile',
    actionRoute: 'edit_profile',
  ),
  BotQA(
    id: 'd_community',
    icon: Icons.groups_rounded,
    question: 'What community resources are available?',
    questionsByLang: {
      'ar': 'ما هي موارد المجتمع المتاحة؟',
      'ckb': 'چ سەرچاوەکانی کۆمەڵگا بەردەستن؟',
      'kmr': 'چ سەرچاوەیێن جڤاکی بەردەستن؟',
    },
    answer:
        'The Community section has local service guides, a city map, partner '
        'organisations and resources to help you engage with the community '
        'around you.',
    answersByLang: {
      'ar': 'يحتوي قسم المجتمع على أدلة الخدمات المحلية وخريطة المدينة والمنظمات الشريكة والموارد التي تساعدك على التفاعل مع مجتمعك.',
      'ckb': 'بەشی کۆمەڵگا ڕێنمایییە خزمەتگوزاریە شوێنییەکانی هەیە، نەخشەی شار، ڕێکخراوە هاوبەشەکان و سەرچاوەکان کە یارمەتیت دەدات پەیوەندی لەگەڵ کۆمەڵگاکەی دەوروبەرت بکەیت.',
      'kmr': 'بەشا جڤاکی رێبەرێن خزمەتگوزاریێن خۆجهی، نەخشەیا باژێری، رێکخراوێن هەڤکار و سەرچاوەیان هەنە دا هاریکاریا تە بکەن پەیوەندیێ دگەل جڤاکا دەوروبەرا خۆ چێبکەی.',
    },
    keywords: ['community', 'local', 'city', 'guide', 'resource', 'partner', 'area'],
    keywordsByLang: {
      'ar': ['مجتمع', 'محلي', 'مدينة', 'دليل', 'موارد'],
      'ckb': ['کۆمەڵگا', 'شوێنی', 'شار', 'ڕێنمایی', 'سەرچاوە'],
      'kmr': ['جڤاک', 'خۆجهی', 'باژێر', 'رێبەر', 'سەرچاوە'],
    },
    actionLabel: 'Open Community',
    actionRoute: 'community',
  ),
  BotQA(
    id: 'd_services',
    icon: Icons.apps_rounded,
    question: 'What other services does the app offer?',
    questionsByLang: {
      'ar': 'ما هي الخدمات الأخرى التي يقدمها التطبيق؟',
      'ckb': 'ئەپەکە چ خزمەتگوزاریی تری پێشکەش دەکات؟',
      'kmr': 'ئەپ چ خزمەتگوزاریێن دی پێشکێش دکەت؟',
    },
    answer:
        'Beyond campaigns and donations the app offers marriage support, Kafala '
        'family sponsorship, the beneficiary marketplace, volunteer '
        'opportunities and local community guides. Open Services to explore '
        'everything.',
    answersByLang: {
      'ar': 'يمكنني مساعدتك في التبرع للحملات، تتبع تبرعاتك، التواصل مع أصحاب الحملات، التسوق في السوق، كفالة أسرة، طلب دعم الزواج، والمزيد. ماذا تريد أن تفعل؟',
      'ckb': 'دەتوانم یارمەتیت بدەم لە بەخشین بۆ کامپەینەکان، شوێنکردنەوەی بەخشینەکانت، گفتوگۆ لەگەڵ خاوەنانی کامپەین، کڕین لە بازاڕ، پاڵپشتی خێزان لەڕێی کەفالەوە، داواکاری پشتگیری زەواج، و زیاتر.',
      'kmr': 'ئەز دشێم هاریکاریا تە بکەم د بەخشینا کامپینان، شوپاندنا بەخشینێن تە، ئاخفتن دگەل خودانێن کامپینان، کڕین ژ بازارێ، پشتگیریا خێزانێ ب کەفالە، داخوازا پشتگیریا هاوسەرگیریێ، و پتر.',
    },
    keywords: ['service', 'other', 'feature', 'app', 'offer', 'what can', 'available', 'list'],
    keywordsByLang: {
      'ar': ['خدمات', 'ماذا يوجد', 'ميزات', 'التطبيق', 'عروض'],
      'ckb': ['خزمەتگوزاری', 'چی هەیە', 'تایبەتمەندی', 'ئەپ'],
      'kmr': ['خزمەتگوزاری', 'چ هەی', 'تایبەتمەندی', 'ئەپ'],
    },
    actionLabel: 'Explore Services',
    actionRoute: 'services',
  ),
  ..._aboutAppQAs,
];

// ─────────────────────────────────────────────────────────────────────────────
// BENEFICIARY  (role 2)
// ─────────────────────────────────────────────────────────────────────────────

const List<BotQA> beneficiaryQAs = [
  BotQA(
    id: 'b_submit',
    icon: Icons.post_add_rounded,
    question: 'How do I submit a project or campaign?',
    questionsByLang: {
      'ar': 'كيف أقدّم مشروعاً أو حملة؟',
      'ckb': 'چۆن پڕۆژەیەک یان کامپەینێک تەقدیم بکەم؟',
      'kmr': 'ئەز چەوا پرۆژەیەکێ یان کامپینەکێ بنێرم؟',
    },
    answer:
        'Use the Submit New Project form to add your title, description, goal '
        'amount and any supporting documents. Tap below to open it — the admin '
        'team reviews it and either approves it or asks for more information.',
    answersByLang: {
      'ar': 'استخدم نموذج تقديم مشروع جديد لإضافة عنوانك ووصفك والمبلغ المستهدف وأي وثائق داعمة. اضغط أدناه لفتحه — يراجعه فريق المشرفين ويوافق عليه أو يطلب مزيداً من المعلومات.',
      'ckb': 'فۆرمی تەقدیمکردنی پڕۆژەی نوێ بەکاربهێنە بۆ زیادکردنی ناونیشان، وەسف، بڕی ئامانج و هەر بەڵگەنامەیەکی پشتگیری. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی — تیمی بەڕێوەبەران پشکنینەوەی دەکات و یان پەسەندی دەکات یان زانیاری زیاتر داوا دەکات.',
      'kmr': 'فۆرما "ناردنا پرۆژەیا نوی" بکار بینە دا ناڤونیشان، پێناسە، بڕی ئامانج و هەر بەلگەیێن پشتگیری زێدە بکەی. ل خوارێ کلیک بکە دا ڤەکەی — تیمێ بەڕێڤەبەری دێ ببینیتە و یان پەسەند دکەت یان زانیاریێن پتر دخوازیت.',
    },
    keywords: ['submit', 'project', 'campaign', 'new', 'create', 'add', 'apply', 'request project'],
    keywordsByLang: {
      'ar': ['تقديم مشروع', 'حملة جديدة', 'إضافة مشروع', 'طلب تمويل', 'نشر مشروع'],
      'ckb': ['تەقدیمکردنی پڕۆژە', 'کامپەینی نوێ', 'پڕۆژەی نوێ', 'داواکاری'],
      'kmr': ['ناردنا پرۆژەی', 'کامپینا نوی', 'داخوازا پرۆژەی'],
    },
    actionLabel: 'Submit a Project',
    actionRoute: 'submit_project',
  ),
  BotQA(
    id: 'b_donations',
    icon: Icons.volunteer_activism_rounded,
    question: 'How do I view donations to my campaigns?',
    questionsByLang: {
      'ar': 'كيف أعرض التبرعات لحملاتي؟',
      'ckb': 'چۆن بەخشینەکانی کامپەینەکانم ببینم؟',
      'kmr': 'ئەز چەوا بەخشینێن کامپینێن خۆ ببینم؟',
    },
    answer:
        'The My Campaign Contributions screen lists all your campaigns and every '
        'donor who contributed, along with their amounts and delivery status. '
        'Tap below to open it.',
    answersByLang: {
      'ar': 'تعرض شاشة تبرعات حملتي جميع حملاتك وكل متبرع ساهم، مع المبالغ وحالة التسليم. اضغط أدناه لفتحها.',
      'ckb': 'شاشەی تۆمارکردنی بەخشینی کامپەینەکانم هەموو کامپەینەکانت و هەموو بەخشەرێک کە بەشداری کردووە لیست دەکات، لەگەڵ بڕەکان و حاڵەتی گەیاندن. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.',
      'kmr': 'سکرینا "بەخشینێن کامپینێن من" هەمی کامپینێن تە و هەر بەخشەرەکێ بەشداربووی، دگەل بڕان و دۆخێ گەهاندنێ لیست دکەت. ل خوارێ کلیک بکە دا ڤەکەی.',
    },
    keywords: ['donat', 'received', 'my campaign', 'how much', 'raised', 'donor list', 'contribution'],
    keywordsByLang: {
      'ar': ['تبرعات حملتي', 'من تبرع', 'مبلغ مجمع', 'المتبرعون', 'تبرعات مستلمة'],
      'ckb': ['بەخشینی کامپەینم', 'کێ بەخشی', 'بڕی کۆکراوەتەوە', 'بەخشەران'],
      'kmr': ['بەخشینێن کامپینێن من', 'کێ بەخشی', 'بەخشەر'],
    },
    actionLabel: 'My Campaign Contributions',
    actionRoute: 'campaign_donations',
  ),
  BotQA(
    id: 'b_chat_donor',
    icon: Icons.chat_bubble_rounded,
    question: 'How do I start a chat with a donor?',
    questionsByLang: {
      'ar': 'كيف أبدأ محادثة مع متبرع؟',
      'ckb': 'چۆن گفتوگۆیەک لەگەڵ بەخشەرێک دەست پێ بکەم؟',
      'kmr': 'ئەز چەوا ئاخفتنەکێ دگەل بەخشەرەکی دەست پێ بکەم؟',
    },
    answer:
        'Open My Campaign Contributions, find the contributor\'s row and tap the chat icon '
        'next to their name. The donor is notified and can accept — then you, '
        'the donor and our support team can message privately.',
    answersByLang: {
      'ar': 'افتح تبرعات حملتي، ابحث عن صف المتبرع واضغط على أيقونة المحادثة بجانب اسمه. سيتلقى المتبرع إشعاراً ويمكنه القبول — ثم يمكنكم أنتم والمتبرع وفريق الدعم التراسل بشكل خاص.',
      'ckb': 'تۆمارکردنی بەخشینی کامپەینەکانم بکەوە، ڕیزەکەی بەخشەر بدۆزەوە و ئایکۆنی گفتوگۆ لەتەنیشت ناوەکەی بپەڕە. بەخشەرەکە ئاگادار دەکرێیتەوە و دەتوانێت قبووڵ بکات — ئەوکات تۆ، بەخشەرەکە و تیمی پشتگیریمان دەتوانن بە تایبەتی پەیامبنێرن.',
      'kmr': 'بەخشینێن کامپینێن خۆ ڤەکە، رێزا بەخشەری بدۆزە و ئایکۆنا ئاخفتنێ ل تەنشتا ناڤێ وی کلیک بکە. بەخشەر دێ ئاگەهدار بیت و دشێت پەسەند بکەت — پاشی تو، بەخشەر و تیمێ پشتگیریا مە دشێن ب تایبەتی پەیاما بشینن.',
    },
    keywords: ['chat', 'donor', 'message', 'contact', 'talk', 'communicate', 'reach donor'],
    keywordsByLang: {
      'ar': ['محادثة متبرع', 'تواصل مع متبرع', 'رسالة للمتبرع', 'كلام المتبرع'],
      'ckb': ['گفتوگۆ', 'بەخشەر', 'پەیام', 'پەیوەندی لەگەڵ بەخشەر'],
      'kmr': ['ئاخفتن', 'بەخشەر', 'پەیام', 'پەیوەندی'],
    },
    actionLabel: 'My Campaign Contributions',
    actionRoute: 'campaign_donations',
  ),
  BotQA(
    id: 'b_pending',
    icon: Icons.pending_actions_rounded,
    question: 'How do I check my pending project requests?',
    questionsByLang: {
      'ar': 'كيف أتحقق من طلبات مشاريعي المعلقة؟',
      'ckb': 'چۆن داواکاریە هەڵواسراوەکانی پڕۆژەکانم بپشکنم؟',
      'kmr': 'ئەز چەوا داخوازێن پرۆژەیێن خۆ یێن چاڤەڕوانیێ ببینم؟',
    },
    answer:
        'The Pending Projects screen lists every submission awaiting admin '
        'approval. Once approved it moves to My Projects and becomes visible to '
        'donors. Tap below to open it.',
    answersByLang: {
      'ar': 'تعرض شاشة المشاريع المعلقة كل طلب ينتظر موافقة المشرف. بعد الموافقة، ينتقل إلى مشاريعي ويصبح مرئياً للمتبرعين. اضغط أدناه لفتحها.',
      'ckb': 'شاشەی پڕۆژەکانی هەڵواسراو هەموو تەقدیمێکی چاوەڕواوی موافەقەتی بەڕێوەبەرانی نیشان دەدات. دوای موافەقەت، بۆ پڕۆژەکانم دەگوازرێتەوە و بۆ بەخشەراکان بەچاوەرواندەکرێت. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.',
      'kmr': 'سکرینا "پرۆژەیێن چاڤەڕوانیێ" هەر ناردنەکا چاڤەڕوانی پەسەندکرنا بەڕێڤەبەری نیشان ددەت. پشتی پەسەندکرنێ، دچیتە "پرۆژەیێن من" و بۆ بەخشەران دیار دبیت. ل خوارێ کلیک بکە دا ڤەکەی.',
    },
    keywords: ['pending', 'review', 'waiting', 'approval', 'status', 'check', 'under review'],
    keywordsByLang: {
      'ar': ['مشاريع معلقة', 'انتظار الموافقة', 'قيد المراجعة', 'حالة الطلب', 'لم يوافق بعد'],
      'ckb': ['هەڵواسراو', 'هەڵچاو', 'چاوەڕوانی موافەقەت', 'حاڵەتی داواکاری'],
      'kmr': ['چاڤەڕوانی', 'ل بەندا پەسەندکرنێ', 'دۆخێ داخوازێ'],
    },
    actionLabel: 'Pending Projects',
    actionRoute: 'pending_projects',
  ),
  BotQA(
    id: 'b_accept_chat',
    icon: Icons.mark_chat_read_rounded,
    question: 'How do I accept or decline a chat request from a donor?',
    questionsByLang: {
      'ar': 'كيف أقبل أو أرفض طلب محادثة من متبرع؟',
      'ckb': 'چۆن داواکارییەکی گفتوگۆ لە بەخشەرێک قبووڵ یان ڕەت بکەمەوە؟',
      'kmr': 'ئەز چەوا داخوازا ئاخفتنێ ژ بەخشەرەکی پەسەند یان ڕەت بکەم؟',
    },
    answer:
        'When a donor requests a chat you get a notification in Alerts with '
        'Accept and Decline buttons right inside it. You can also accept or '
        'decline from the top of the Messages tab.',
    answersByLang: {
      'ar': 'عندما يطلب متبرع محادثة، ستتلقى إشعاراً في التنبيهات بزري القبول والرفض مباشرة فيه. يمكنك أيضاً القبول أو الرفض من أعلى تبويب الرسائل.',
      'ckb': 'کاتێک بەخشەرێک گفتوگۆ داوا دەکات، ئاگادارکردنەوەیەکت لە تابی ئاگادارکردنەوەکان دەگات لەگەڵ تەکمەکانی قبووڵکردن و ڕەتکردنەوە ڕاستەوخۆ تیایدا. دەتوانیت هەروەها قبووڵ بکەیت یان ڕەتی بکەیتەوە لە سەرەوەی تابی پەیامەکان.',
      'kmr': 'دەمێ بەخشەرەک داخوازا ئاخفتنێ دکەت، دێ ئاگەهداریەک د تابا ئاگەهداریان دا دگەل دوگمەیێن پەسەندکرن و ڕەتکرنێ رەستەوخۆ تێدا بگری. تو دشێی هەروەسا ژ سەرێ تابا پەیامان پەسەند یان ڕەت بکەی.',
    },
    keywords: ['accept', 'decline', 'chat request', 'request', 'incoming', 'donor ask'],
    keywordsByLang: {
      'ar': ['قبول محادثة', 'رفض محادثة', 'طلب محادثة', 'موافقة على محادثة'],
      'ckb': ['قبووڵکردن', 'ڕەتکردنەوە', 'داواکاریی گفتوگۆ', 'موافەقەت'],
      'kmr': ['پەسەندکرن', 'ڕەتکرن', 'داخوازا ئاخفتنێ'],
    },
    actionLabel: 'Go to Alerts',
    actionRoute: 'alerts',
  ),
  BotQA(
    id: 'b_market',
    icon: Icons.storefront_rounded,
    question: 'How do I sell products in the marketplace?',
    questionsByLang: {
      'ar': 'كيف أبيع منتجات في السوق؟',
      'ckb': 'چۆن بەرهەم لە بازاڕ بفرۆشم؟',
      'kmr': 'ئەز چەوا بەرهەمان د بازارێ دا بفرۆشم؟',
    },
    answer:
        'Go to Services to add a marketplace listing — photos, a price and a '
        'description. Once approved, donors browsing the Market can buy it, '
        'giving you a direct source of income.',
    answersByLang: {
      'ar': 'اذهب إلى الخدمات لإضافة قائمة في السوق — ارفع صوراً وسعراً ووصفاً. بعد الموافقة، يمكن للمتبرعين المتصفحين في السوق شراؤه، مما يوفر لك مصدر دخل مباشر.',
      'ckb': 'بچۆ بۆ خزمەتگوزارییەکان بۆ زیادکردنی لیستە بازاڕییەکە — وێنە، نرخ و وەسف بکەوتەوە. دوای موافەقەت، بەخشەرانی گەڕانی بازاڕ دەتوانن بیکڕن، کە سەرچاوەیەکی داهاتی ڕاستەوخۆت پێ دەبەخشێت.',
      'kmr': 'بچۆ خزمەتگوزاریان دا لیستەیەکا بازارێ زێدە بکەی — وێنە، بها و پێناسە. پشتی پەسەندکرنێ، بەخشەرێن د بازارێ دا دگەڕن دشێن بکڕن، کو سەرچاوەیەکا داهاتی رەستەوخۆ ددەتە تە.',
    },
    keywords: ['sell', 'market', 'product', 'list', 'shop', 'income', 'marketplace', 'put'],
    keywordsByLang: {
      'ar': ['بيع', 'سوق', 'منتجات', 'دخل', 'قائمة منتج', 'بيع منتجات'],
      'ckb': ['فرۆشتن', 'بازاڕ', 'بەرهەم', 'داهات'],
      'kmr': ['فرۆتن', 'بازار', 'بەرهەم', 'داهات'],
    },
    actionLabel: 'Open Services',
    actionRoute: 'services',
  ),
  BotQA(
    id: 'b_profile',
    icon: Icons.person_rounded,
    question: 'How do I edit my profile?',
    questionsByLang: {
      'ar': 'كيف أعدّل ملفي الشخصي؟',
      'ckb': 'چۆن پرۆفایلەکەم دەستکاری بکەم؟',
      'kmr': 'ئەز چەوا پرۆفایلا خۆ دەستکاری بکەم؟',
    },
    answer:
        'Keep your contact details and photo current on the Edit Profile screen '
        '— donors and the support team see your profile when reviewing your '
        'campaigns. Tap below to open it.',
    answersByLang: {
      'ar': 'احتفظ ببيانات الاتصال وصورتك محدّثة في شاشة تعديل الملف الشخصي — يرى المتبرعون وفريق الدعم ملفك الشخصي عند مراجعة حملاتك. اضغط أدناه لفتحها.',
      'ckb': 'وردەکاریی پەیوەندی و وێنەکەت کاتبەکات لە شاشەی دەستکاریکردنی پرۆفایل — بەخشەران و تیمی پشتگیری پرۆفایلەکەت دەبینن کاتێک کامپەینەکانت پشکنینەوە دەکەن. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.',
      'kmr': 'وردەکاریێن پەیوەندیێ و وێنەیێ خۆ ل سەر سکرینا دەستکاریا پرۆفایلێ رۆژانە بهێلە — بەخشەر و تیمێ پشتگیری پرۆفایلا تە دەمێ کامپینێن تە ددەنە بەر چاڤان دبینن. ل خوارێ کلیک بکە دا ڤەکەی.',
    },
    keywords: ['profile', 'edit', 'update', 'name', 'photo', 'account', 'setting'],
    keywordsByLang: {
      'ar': ['ملف شخصي', 'تعديل', 'بياناتي', 'صورة', 'معلوماتي'],
      'ckb': ['پرۆفایل', 'دەستکاریکردن', 'زانیاریم', 'وێنە'],
      'kmr': ['پرۆفایل', 'دەستکاری', 'زانیاریێن من'],
    },
    actionLabel: 'Edit Profile',
    actionRoute: 'edit_profile',
  ),
  BotQA(
    id: 'b_community',
    icon: Icons.groups_rounded,
    question: 'What community resources are available to me?',
    questionsByLang: {
      'ar': 'ما هي موارد المجتمع المتاحة لي؟',
      'ckb': 'چ سەرچاوەکانی کۆمەڵگا بۆ من بەردەستن؟',
      'kmr': 'چ سەرچاوەیێن جڤاکی بۆ من بەردەستن؟',
    },
    answer:
        'The Community section has local service guides, partner organisations '
        'and city-level resources to help you access support in your area.',
    answersByLang: {
      'ar': 'يحتوي قسم المجتمع على أدلة الخدمات المحلية والمنظمات الشريكة والموارد على مستوى المدينة لمساعدتك على الوصول إلى الدعم في منطقتك.',
      'ckb': 'بەشی کۆمەڵگا ڕێنماییی خزمەتگوزاریی شوێنی، ڕێکخراوە هاوبەشەکان و سەرچاوەکانی ئاستی شار هەیە بۆ یارمەتیدانت لە دەستگەیشتن بۆ پشتگیری لە ناوچەکەت.',
      'kmr': 'بەشا جڤاکی رێبەرێن خزمەتگوزاریێن خۆجهی، رێکخراوێن هەڤکار و سەرچاوەیێن ل ئاستێ باژێری هەنە دا هاریکاریا تە بکەن د گەهشتنا پشتگیریێ ل دەڤەرا خۆ.',
    },
    keywords: ['community', 'resource', 'local', 'city', 'service', 'guide', 'near'],
    keywordsByLang: {
      'ar': ['مجتمع', 'موارد', 'خدمات محلية', 'المنطقة'],
      'ckb': ['کۆمەڵگا', 'سەرچاوە', 'خزمەتگوزارییە شوێنییەکان'],
      'kmr': ['جڤاک', 'سەرچاوە', 'خزمەتگوزاریێن خۆجهی'],
    },
    actionLabel: 'Open Community',
    actionRoute: 'community',
  ),
  BotQA(
    id: 'b_support',
    icon: Icons.support_agent_rounded,
    question: 'How do I get help from the support team?',
    questionsByLang: {
      'ar': 'كيف أحصل على مساعدة من فريق الدعم؟',
      'ckb': 'چۆن یارمەتی لە تیمی پشتگیری وەربگرم؟',
      'kmr': 'ئەز چەوا هاریکاریێ ژ تیمێ پشتگیری وەربگرم؟',
    },
    answer:
        'Use the Support form to message our team — we aim to respond within 24 '
        'hours. For urgent matters you can reply directly to any notification '
        'from us. Tap below to open it.',
    answersByLang: {
      'ar': 'استخدم نموذج الدعم لمراسلة فريقنا — نهدف إلى الرد خلال 24 ساعة. للأمور العاجلة، يمكنك الرد مباشرة على أي إشعار منا. اضغط أدناه لفتحه.',
      'ckb': 'فۆرمی پشتگیری بەکاربهێنە بۆ ئەوەی نامەی تیمەکەمان بنێریت — ئامانجمان وەڵامدانەوە لە ماوەی ٢٤ کاتژمێردایە. بۆ کارەکانی ئازگیر دەتوانیت ڕاستەوخۆ وەڵامی هەر ئاگادارکردنەوەیەک بدەیتەوە. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.',
      'kmr': 'فۆرما پشتگیریێ بکار بینە دا پەیاما بۆ تیمێ مە بشینی — ئامانجا مە ئەوە کو د ناڤ ٢٤ دەمژمێران دا بەرسڤ بدەین. بۆ کارێن لەزگین تو دشێی رەستەوخۆ بەرسڤا هەر ئاگەهداریەکێ ژ مە بدەی. ل خوارێ کلیک بکە دا ڤەکەی.',
    },
    keywords: ['support', 'help', 'contact', 'team', 'admin', 'issue', 'problem', 'ticket'],
    keywordsByLang: {
      'ar': ['دعم', 'مساعدة', 'فريق الدعم', 'مشكلة', 'تذكرة', 'تواصل مع الفريق'],
      'ckb': ['پشتگیری', 'یارمەتی', 'تیمی پشتگیری', 'کێشە', 'پرۆبلیم'],
      'kmr': ['پشتگیری', 'هاریکاری', 'تیمێ پشتگیری', 'کێشە'],
    },
    actionLabel: 'Contact Support',
    actionRoute: 'support',
  ),
  BotQA(
    id: 'b_messages',
    icon: Icons.forum_rounded,
    question: 'Where do I find my accepted conversations?',
    questionsByLang: {
      'ar': 'أين أجد محادثاتي المقبولة؟',
      'ckb': 'گفتوگۆ قبووڵکراوەکانم لە کوێ دەدۆزمەوە؟',
      'kmr': 'ئاخفتنێن خۆ یێن پەسەندکری ل کیڤە ببینم؟',
    },
    answer:
        'Once a chat request is accepted by either side, the conversation '
        'appears in the Messages tab. Our support team is included in every '
        'chat for your safety.',
    answersByLang: {
      'ar': 'بمجرد قبول طلب محادثة من أي طرف، تظهر المحادثة في تبويب الرسائل. فريق الدعم لدينا متضمن في كل محادثة لسلامتك.',
      'ckb': 'کاتێک داواکارییەکی گفتوگۆ لەلایەن هەر لاوێک قبووڵ کرا، گفتوگۆکە لە تابی پەیامەکان دەردەکەوێت. تیمی پشتگیریمان لە هەموو گفتوگۆیەک بۆ ئاسایشت تێ دایە.',
      'kmr': 'دەمێ داخوازا ئاخفتنێ ژ لایێ هەر دوو لایان ڤە هاتە پەسەندکرن، ئاخفتن د تابا پەیامان دا دیار دبیت. تیمێ پشتگیریا مە د هەر ئاخفتنەکێ دا بۆ سەلامەتیا تە هەیە.',
    },
    keywords: ['messages', 'accepted', 'conversation', 'thread', 'inbox', 'chat list', 'open chat'],
    keywordsByLang: {
      'ar': ['رسائل', 'محادثات', 'صندوق الوارد', 'الرسائل المقبولة', 'محادثاتي'],
      'ckb': ['پەیامەکان', 'گفتوگۆکان', 'باسکردنەکان', 'ئینبۆکس'],
      'kmr': ['پەیام', 'ئاخفتن', 'ئینبۆکس', 'گفتوگۆ'],
    },
    actionLabel: 'Open Messages',
    actionRoute: 'messages',
  ),
  ..._aboutAppQAs,
];

// ─────────────────────────────────────────────────────────────────────────────
// VOLUNTEER  (role 3)
// ─────────────────────────────────────────────────────────────────────────────

const List<BotQA> volunteerQAs = [
  BotQA(
    id: 'v_missions',
    icon: Icons.assignment_rounded,
    question: 'How do I see available missions?',
    questionsByLang: {
      'ar': 'كيف أرى المهام المتاحة؟',
      'ckb': 'چۆن ئەرکە بەردەستەکان ببینم؟',
      'kmr': 'ئەز چەوا ئەرکێن بەردەست ببینم؟',
    },
    answer:
        'Open the Volunteer section. All active missions are listed with their '
        'task description, location, required skills and timing. Tap any mission '
        'to read the full details before applying.',
    answersByLang: {
      'ar': 'افتح تبويب التطوع لرؤية جميع المهام النشطة مع وصف المهمة والموقع والمهارات المطلوبة والتوقيت. اضغط على أي مهمة لقراءة التفاصيل الكاملة.',
      'ckb': 'تابی ڕاهێنان بکەوە بۆ دیتنی هەموو ئەرکە چالاکەکان لەگەڵ وەسفی ئەرک، شوێن، مەهارەتی پێویست و کات. لەسەر هەر ئەرکێک بپەڕە بۆ خوێندنەوەی وردەکاری تەواو.',
      'kmr': 'تابا خۆبەخشیێ ڤەکە دا هەمی ئەرکێن چالاک دگەل پێناسەیا ئەرکی، جه، شیانێن پێدڤی و دەمی ببینی. ل هەر ئەرکەکێ کلیک بکە دا وردەکاریێن تەمام بخوینی.',
    },
    keywords: ['mission', 'task', 'job', 'available', 'volunteer', 'work', 'see missions'],
    keywordsByLang: {
      'ar': ['مهمة', 'عمل تطوعي', 'فرص تطوع', 'مهام متاحة', 'ماذا أفعل'],
      'ckb': ['ئەرک', 'کاری ڕاهێنانی', 'دەرفەتە ڕاهێنانییەکان'],
      'kmr': ['ئەرک', 'خۆبەخشی', 'دەرفەت'],
    },
    actionLabel: 'Open Volunteer',
    actionRoute: 'volunteer',
  ),
  BotQA(
    id: 'v_signup',
    icon: Icons.how_to_reg_rounded,
    question: 'How do I sign up for a mission?',
    questionsByLang: {
      'ar': 'كيف أسجّل في مهمة؟',
      'ckb': 'چۆن خۆم بۆ ئەرکێک تۆمار بکەم؟',
      'kmr': 'ئەز چەوا بۆ ئەرکەکێ تۆمار ببم؟',
    },
    answer:
        'In the Volunteer section, tap the mission you want and then "Apply". '
        'The coordinator reviews your application and confirms — you\'ll be '
        'notified in Alerts.',
    answersByLang: {
      'ar': 'في تبويب التطوع، اضغط على المهمة التي تريدها ثم "تقدم". يراجع المنسق طلبك ويؤكد — ستتلقى إشعاراً في التنبيهات.',
      'ckb': 'لە تابی ڕاهێنان، لەسەر ئەرکی دەویت بپەڕە ئەوکات "تەقدیم بکە". هەماهەنگکەرەکە تەقدیمەکەت پشکنینەوە دەکات و پشتگیری دەکات — لە تابی ئاگادارکردنەوەکان ئاگادارت دەکرێتەوە.',
      'kmr': 'د تابا خۆبەخشیێ دا، ل ئەرکێ کو دخوازی کلیک بکە و پاشی "داخواز بکە". هەماهەنگکار داخوازا تە ددەتە بەر چاڤان و پشتراست دکەت — دێ د ئاگەهداریان دا ئاگەهدار بی.',
    },
    keywords: ['sign up', 'join', 'apply', 'register', 'participate', 'enroll', 'how to join'],
    keywordsByLang: {
      'ar': ['تسجيل تطوع', 'انضمام', 'تقديم طلب تطوع', 'مشاركة'],
      'ckb': ['تۆمارکردن', 'بەشدار', 'تەقدیم', 'چۆن تۆمار بکەم'],
      'kmr': ['تۆمارکرن', 'بەشداری', 'داخواز', 'چەوا بەشداری بکەم'],
    },
    actionLabel: 'Open Volunteer',
    actionRoute: 'volunteer',
  ),
  BotQA(
    id: 'v_history',
    icon: Icons.history_rounded,
    question: 'How do I view my volunteer history?',
    questionsByLang: {
      'ar': 'كيف أعرض سجل تطوعي؟',
      'ckb': 'چۆن مێژووی ڕاهێنانم ببینم؟',
      'kmr': 'ئەز چەوا مێژووا خۆبەخشیا خۆ ببینم؟',
    },
    answer:
        'Your completed missions and logged hours are recorded in the Volunteer '
        'section — scroll to the history list to review all your contributions.',
    answersByLang: {
      'ar': 'مهامك المكتملة وساعاتك المسجلة مسجلة في قسم التطوع — مرر للأسفل إلى قائمة السجل لمراجعة جميع مساهماتك.',
      'ckb': 'ئەرکە تەواوبووەکانت و کاتژمێرە تۆمارکراوەکانت لە بەشی ڕاهێناندا تۆماردراون — بخلیزە خوارەوە بۆ لیستی مێژوو بۆ پشکنینەوەی هەموو بەشداریکردنەکانت.',
      'kmr': 'ئەرکێن تە یێن تەمامکری و دەمژمێرێن تۆمارکری د بەشا خۆبەخشیێ دا تێنە تۆمارکرن — بۆ خوارێ بخلیزینە بۆ لیستا مێژوویێ دا هەمی بەشداریێن خۆ ببینی.',
    },
    keywords: ['history', 'past', 'completed', 'record', 'my mission', 'hours', 'previous'],
    keywordsByLang: {
      'ar': ['سجل التطوع', 'مهام مكتملة', 'ساعات التطوع', 'تاريخ'],
      'ckb': ['مێژووی ڕاهێنان', 'ئەرکی تەواوبووم', 'کاتژمێرەکانم'],
      'kmr': ['مێژووا خۆبەخشیێ', 'ئەرکێن تەمامکری', 'دەمژمێرێن من'],
    },
    actionLabel: 'Open Volunteer',
    actionRoute: 'volunteer',
  ),
  BotQA(
    id: 'v_skills',
    icon: Icons.star_rounded,
    question: 'How do I update my skills and availability?',
    questionsByLang: {
      'ar': 'كيف أحدّث مهاراتي وتوافري؟',
      'ckb': 'چۆن مەهارەت و بەردەستبوونم نوێ بکەمەوە؟',
      'kmr': 'ئەز چەوا شیان و بەردەستبوونا خۆ نویکەم؟',
    },
    answer:
        'Your skills and schedule live in your profile. Open the Edit Profile '
        'screen to update your skills, availability and any certifications so '
        'coordinators can match you to the right missions.',
    answersByLang: {
      'ar': 'مهاراتك وجدولك موجودان في ملفك الشخصي. افتح شاشة تعديل الملف الشخصي لتحديث مهاراتك وتوافرك وأي شهادات حتى يتمكن المنسقون من مطابقتك مع المهام المناسبة.',
      'ckb': 'مەهارەت و خشتەکانت لە پرۆفایلەکەتدا دەژین. شاشەی دەستکاریکردنی پرۆفایل بکەوە بۆ نوێکردنەوەی مەهارەت، بەردەستبوون و هەر تایبەتمەندیەک تا هەماهەنگکەران بتوانن بیانتەبقینن لەگەڵ ئەرکەکانی گونجاو.',
      'kmr': 'شیان و خشتەیا تە د پرۆفایلا تە دا نە. سکرینا دەستکاریا پرۆفایلێ ڤەکە دا شیان، بەردەستبوون و هەر بڕوانامەیان نویکەی دا هەماهەنگکار بشێن تە دگەل ئەرکێن گونجای رێک بخن.',
    },
    keywords: ['skill', 'availability', 'profile', 'update', 'experience', 'cert', 'schedule'],
    keywordsByLang: {
      'ar': ['مهارات', 'توافر', 'جدول زمني', 'تحديث مهاراتي'],
      'ckb': ['مەهارەت', 'بەردەستبوون', 'خشتە', 'نوێکردنەوەی مەهارەت'],
      'kmr': ['شیان', 'بەردەستبوون', 'خشتەیا من'],
    },
    actionLabel: 'Edit Profile',
    actionRoute: 'edit_profile',
  ),
  BotQA(
    id: 'v_notifications',
    icon: Icons.notifications_active_rounded,
    question: 'How do I get notified about new missions?',
    questionsByLang: {
      'ar': 'كيف أتلقى إشعارات عن المهام الجديدة؟',
      'ckb': 'چۆن دەربارەی ئەرکی نوێ ئاگادار بکرێمەوە؟',
      'kmr': 'ئەز چەوا دەربارەی ئەرکێن نوی ئاگەهدار ببم؟',
    },
    answer:
        'Notifications about new missions, urgent assignments and status updates '
        'appear in the Alerts tab. Keep phone notifications enabled so you don\'t '
        'miss time-sensitive tasks.',
    answersByLang: {
      'ar': 'تظهر إشعارات المهام الجديدة والمهام العاجلة وتحديثات الحالة في تبويب التنبيهات. أبق إشعارات الهاتف مفعّلة حتى لا تفوتك المهام الحساسة للوقت.',
      'ckb': 'ئاگادارکردنەوەکانی بارەی ئەرکی نوێ، ئەرکی ئازگیر و نوێکردنەوەی حاڵەت لە تابی ئاگادارکردنەوەکان دەردەکەون. ئاگادارکردنەوەکانی تەلەفۆن چالاک بهێڵەوە تا ئەرکە کاتژمێرییەکان لەدەستت نەچن.',
      'kmr': 'ئاگەهداریێن دەربارەی ئەرکێن نوی، ئەرکێن لەزگین و نویکرنا دۆخی د تابا ئاگەهداریان دا دیار دبن. ئاگەهداریێن مۆبایلی چالاک بهێلە دا ئەرکێن دەمدار ژ دەست نەدەی.',
    },
    keywords: ['notif', 'alert', 'new mission', 'update', 'inform', 'remind'],
    keywordsByLang: {
      'ar': ['إشعارات', 'تنبيهات', 'مهام جديدة', 'تحديثات'],
      'ckb': ['ئاگادارکردنەوە', 'تنبیه', 'ئەرکی نوێ', 'نوێکردنەوە'],
      'kmr': ['ئاگەهداری', 'هشیاری', 'ئەرکێن نوی'],
    },
    actionLabel: 'Go to Alerts',
    actionRoute: 'alerts',
  ),
  BotQA(
    id: 'v_community',
    icon: Icons.groups_rounded,
    question: 'What community resources can I access?',
    questionsByLang: {
      'ar': 'ما هي موارد المجتمع التي يمكنني الوصول إليها؟',
      'ckb': 'چ سەرچاوەکانی کۆمەڵگا دەتوانم دەستیان بکەوم؟',
      'kmr': 'ئەز دشێم گەهشتنا چ سەرچاوەیێن جڤاکی بکەم؟',
    },
    answer:
        'The Community section has local service guides, partner info and the '
        'city map — all useful for field volunteer work and understanding the '
        'areas you\'ll be working in.',
    answersByLang: {
      'ar': 'يحتوي قسم المجتمع على أدلة الخدمات المحلية ومعلومات الشركاء وخريطة المدينة — مفيدة للعمل الميداني وفهم المناطق التي ستعمل فيها.',
      'ckb': 'بەشی کۆمەڵگا ڕێنمایییە خزمەتگوزاریی شوێنییەکانی هەیە، زانیاری هاوبەش و نەخشەی شار — سوودمەندن بۆ کاری مەیدانی و تێگەیشتن لە ناوچەکانی کارکردن.',
      'kmr': 'بەشا جڤاکی رێبەرێن خزمەتگوزاریێن خۆجهی، زانیاریێن هەڤکاران و نەخشەیا باژێری هەنە — بۆ کارێ مەیدانی و تێگەهشتنا دەڤەرێن کو تو تێدا کار دکەی سوودمەند.',
    },
    keywords: ['community', 'local', 'city', 'resource', 'map', 'guide', 'area'],
    keywordsByLang: {
      'ar': ['مجتمع', 'خريطة', 'دليل', 'موارد محلية'],
      'ckb': ['کۆمەڵگا', 'شوێنی', 'شار', 'نەخشە', 'سەرچاوە'],
      'kmr': ['جڤاک', 'خۆجهی', 'باژێر', 'نەخشە'],
    },
    actionLabel: 'Open Community',
    actionRoute: 'community',
  ),
  BotQA(
    id: 'v_support',
    icon: Icons.support_agent_rounded,
    question: 'How do I contact the coordination team?',
    questionsByLang: {
      'ar': 'كيف أتواصل مع فريق التنسيق؟',
      'ckb': 'چۆن پەیوەندی بە تیمی هەماهەنگکردنەوە بکەم؟',
      'kmr': 'ئەز چەوا پەیوەندیێ دگەل تیمێ هەماهەنگیێ بکەم؟',
    },
    answer:
        'Use the Support form to message our coordination team. For urgent field '
        'issues, reply directly to any mission notification in your Alerts tab. '
        'Tap below to open it.',
    answersByLang: {
      'ar': 'استخدم نموذج الدعم لمراسلة فريق التنسيق لدينا. للمشكلات الميدانية العاجلة، رد مباشرة على أي إشعار مهمة في تبويب التنبيهات. اضغط أدناه لفتحه.',
      'ckb': 'فۆرمی پشتگیری بەکاربهێنە بۆ ئەوەی نامەی تیمی هەماهەنگکردنەکەمان بنێریت. بۆ کارەکانی مەیدانی ئازگیر، ڕاستەوخۆ وەڵامی هەر ئاگادارکردنەوەیەکی ئەرک بدەرەوە لە تابی ئاگادارکردنەوەکانت. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.',
      'kmr': 'فۆرما پشتگیریێ بکار بینە دا پەیاما بۆ تیمێ هەماهەنگیا مە بشینی. بۆ کێشەیێن مەیدانی یێن لەزگین، رەستەوخۆ بەرسڤا هەر ئاگەهداریا ئەرکێ د تابا ئاگەهداریان دا بدە. ل خوارێ کلیک بکە دا ڤەکەی.',
    },
    keywords: ['contact', 'coordinator', 'support', 'help', 'team', 'admin', 'issue', 'problem'],
    keywordsByLang: {
      'ar': ['دعم', 'منسق', 'مساعدة', 'مشكلة ميدانية', 'فريق التنسيق'],
      'ckb': ['پشتگیری', 'هەماهەنگکەر', 'یارمەتی', 'کێشەی مەیدانی'],
      'kmr': ['پشتگیری', 'هەماهەنگکار', 'هاریکاری', 'کێشە'],
    },
    actionLabel: 'Contact Support',
    actionRoute: 'support',
  ),
  BotQA(
    id: 'v_profile',
    icon: Icons.person_rounded,
    question: 'How do I edit my profile?',
    questionsByLang: {
      'ar': 'كيف أعدّل ملفي الشخصي؟',
      'ckb': 'چۆن پرۆفایلەکەم دەستکاری بکەم؟',
      'kmr': 'ئەز چەوا پرۆفایلا خۆ دەستکاری بکەم؟',
    },
    answer:
        'Keep your contact details and availability up to date on the Edit '
        'Profile screen so coordinators can reach you and match you to the right '
        'missions. Tap below to open it.',
    answersByLang: {
      'ar': 'احتفظ ببيانات الاتصال وتوافرك محدّثة في شاشة تعديل الملف الشخصي حتى يتمكن المنسقون من التواصل معك. اضغط أدناه لفتحها.',
      'ckb': 'وردەکاریی پەیوەندی و بەردەستبوونت کاتبەکات لە شاشەی دەستکاریکردنی پرۆفایل تا هەماهەنگکەران بتوانن پەیوەندیت پێوە بکەن. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.',
      'kmr': 'وردەکاریێن پەیوەندیێ و بەردەستبوونا خۆ ل سەر سکرینا دەستکاریا پرۆفایلێ رۆژانە بهێلە دا هەماهەنگکار بشێن پەیوەندیێ دگەل تە بکەن. ل خوارێ کلیک بکە دا ڤەکەی.',
    },
    keywords: ['profile', 'edit', 'update', 'name', 'photo', 'account', 'setting'],
    keywordsByLang: {
      'ar': ['ملف شخصي', 'تعديل', 'بياناتي', 'معلوماتي'],
      'ckb': ['پرۆفایل', 'دەستکاریکردن', 'زانیاریم'],
      'kmr': ['پرۆفایل', 'دەستکاری', 'زانیاریێن من'],
    },
    actionLabel: 'Edit Profile',
    actionRoute: 'edit_profile',
  ),
  ..._aboutAppQAs,
];
