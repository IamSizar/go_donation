// Phase 27.8 — recommended push-notification templates for the /push page.
//
// One-tap shortcuts for common occasions (Eid, Jumu'ah, Ramadan, seasonal
// appeals, donor thank-yous). Each carries an English + Arabic title and
// body; the admin picks the language with a toggle and the chosen text
// drops into the compose form's Title/Text fields. The admin can still
// hand-edit before sending.
//
// Pure data — no React here so it can be unit-tested or reused later by a
// scheduled-send feature without pulling in the page component.

import type { LucideIcon } from 'lucide-react'
import {
  MoonStar,
  Moon,
  UtensilsCrossed,
  Sparkles,
  PartyPopper,
  Gift,
  HandCoins,
  Snowflake,
  Baby,
  HeartHandshake,
  Siren,
  Heart,
} from 'lucide-react'

export type TemplateLang = 'en' | 'ar'

export interface PushTemplate {
  /** Stable key (used as the card React key). */
  id: string
  /** Lucide icon component rendered in the card's badge. */
  icon: LucideIcon
  /** Short card label (English — the admin UI chrome stays English). */
  label: string
  /** One-line occasion descriptor shown under the label. */
  tagline: string
  /** Accent hex — tints the icon badge, border, and active state. */
  accent: string
  title: { en: string; ar: string }
  body: { en: string; ar: string }
}

export const PUSH_TEMPLATES: PushTemplate[] = [
  {
    id: 'jumuah',
    icon: MoonStar,
    label: "Jumu'ah Mubarak",
    tagline: 'Weekly Friday blessing',
    accent: '#0F766E',
    title: { en: "Jumu'ah Mubarak 🕌", ar: 'جمعة مباركة 🕌' },
    body: {
      en: 'May this blessed Friday bring you peace and reward. A small gift today reaches a family in need — give your Sadaqah now.',
      ar: 'نتمنى أن يحمل لكم هذا اليوم المبارك السلام والأجر. تبرّعك اليوم يصل إلى عائلة محتاجة — تصدّق الآن.',
    },
  },
  {
    id: 'ramadan',
    icon: Moon,
    label: 'Ramadan Kareem',
    tagline: 'Start of the holy month',
    accent: '#6366F1',
    title: { en: 'Ramadan Kareem 🌙', ar: 'رمضان كريم 🌙' },
    body: {
      en: 'Ramadan is here — the month of mercy and giving. Let your generosity feed and comfort those who need it most.',
      ar: 'حلّ رمضان، شهر الرحمة والعطاء. اجعل كرمك يُطعِم ويواسي من هم في أمسّ الحاجة.',
    },
  },
  {
    id: 'iftar',
    icon: UtensilsCrossed,
    label: 'Iftar Sponsor',
    tagline: 'Sponsor a fasting family',
    accent: '#F59E0B',
    title: { en: 'Sponsor an Iftar tonight 🍽️', ar: 'ارعَ إفطار صائم الليلة 🍽️' },
    body: {
      en: 'No one should break their fast hungry. Sponsor an iftar meal tonight and share the blessing of Ramadan with a fasting family.',
      ar: 'لا أحد يجب أن يفطر جائعاً. ارعَ وجبة إفطار الليلة وشارك بركة رمضان مع عائلة صائمة.',
    },
  },
  {
    id: 'laylat_alqadr',
    icon: Sparkles,
    label: 'Laylat al-Qadr',
    tagline: 'The night of a thousand months',
    accent: '#8B5CF6',
    title: { en: 'The best night for giving ✨', ar: 'أفضل ليلة للعطاء ✨' },
    body: {
      en: 'A deed on Laylat al-Qadr is better than a thousand months. Multiply your reward tonight — give generously while the night lasts.',
      ar: 'العمل في ليلة القدر خير من ألف شهر. ضاعِف أجرك الليلة — تبرّع بسخاء ما دامت الليلة قائمة.',
    },
  },
  {
    id: 'eid_fitr',
    icon: PartyPopper,
    label: 'Eid al-Fitr',
    tagline: 'Celebrate the end of Ramadan',
    accent: '#10B981',
    title: { en: 'Eid Mubarak! 🌙', ar: 'عيد فطر مبارك! 🌙' },
    body: {
      en: 'Eid Mubarak to you and your loved ones! May your fasting and prayers be accepted, your home be filled with joy, and your kindness return to you multiplied. Share the happiness of Eid with a family who has little — your gift turns their Eid into a celebration too.',
      ar: 'عيد فطر مبارك لكم ولأحبائكم! تقبّل الله صيامكم وقيامكم، وملأ بيوتكم فرحاً، وردّ إحسانكم أضعافاً مضاعفة. شاركوا فرحة العيد مع عائلة لا تملك الكثير — تبرّعكم يحوّل عيدهم إلى احتفال أيضاً.',
    },
  },
  {
    id: 'eid_adha',
    icon: Gift,
    label: 'Eid al-Adha',
    tagline: 'Share your Qurbani',
    accent: '#E11D48',
    title: { en: 'Eid al-Adha Mubarak 🐑', ar: 'عيد أضحى مبارك 🐑' },
    body: {
      en: 'Eid al-Adha Mubarak! On this blessed Eid of sacrifice, share your Qurbani with families who rarely taste meat. Your offering feeds the hungry and brings the joy of Eid to those who need it most — may it be accepted from you.',
      ar: 'عيد أضحى مبارك! في عيد التضحية المبارك، شاركوا أضحيتكم مع عائلات قلّما تذوق اللحم. أضحيتكم تُطعِم الجائع وتُدخِل فرحة العيد على من هم في أشدّ الحاجة — تقبّل الله منكم.',
    },
  },
  {
    id: 'zakat',
    icon: HandCoins,
    label: 'Zakat Reminder',
    tagline: 'Annual obligatory charity',
    accent: '#0891B2',
    title: { en: 'Have you given your Zakat? 🤲', ar: 'هل أدّيت زكاتك؟ 🤲' },
    body: {
      en: 'Zakat purifies your wealth and lifts a family out of hardship. Calculate and give your Zakat today — it reaches those who truly deserve it.',
      ar: 'الزكاة تطهّر مالك وتنتشل عائلة من الضيق. احسب زكاتك وأدِّها اليوم — تصل إلى مستحقّيها فعلاً.',
    },
  },
  {
    id: 'winter',
    icon: Snowflake,
    label: 'Winter Relief',
    tagline: 'Seasonal cold-weather appeal',
    accent: '#0EA5E9',
    title: { en: 'Keep a family warm this winter ❄️', ar: 'ادفئ عائلة هذا الشتاء ❄️' },
    body: {
      en: 'The cold is here and many families have no heating. Your gift provides blankets, fuel and warm shelter — give warmth today.',
      ar: 'حلّ البرد وكثير من العائلات بلا تدفئة. تبرّعك يوفّر البطانيات والوقود والمأوى الدافئ — امنح الدفء اليوم.',
    },
  },
  {
    id: 'orphan',
    icon: Baby,
    label: 'Orphan Sponsor',
    tagline: 'Monthly child sponsorship',
    accent: '#EC4899',
    title: { en: 'Sponsor an orphan this month 👶', ar: 'اكفل يتيماً هذا الشهر 👶' },
    body: {
      en: 'Be the reason an orphan smiles. Your monthly sponsorship covers food, clothing and schooling — change a child’s whole future.',
      ar: 'كن سبباً في ابتسامة يتيم. كفالتك الشهرية تغطّي الطعام والكساء والتعليم — غيّر مستقبل طفل بأكمله.',
    },
  },
  {
    id: 'sadaqah',
    icon: HeartHandshake,
    label: 'Sadaqah',
    tagline: 'Everyday voluntary giving',
    accent: '#D946EF',
    title: { en: 'A small Sadaqah, a big change 💝', ar: 'صدقة صغيرة، أثر كبير 💝' },
    body: {
      en: 'Charity never decreases wealth. Even a small Sadaqah today brings relief to someone in need and blessing to your day.',
      ar: 'ما نقص مالٌ من صدقة. حتى صدقة صغيرة اليوم تُفرّج عن محتاج وتبارك يومك.',
    },
  },
  {
    id: 'emergency',
    icon: Siren,
    label: 'Emergency Appeal',
    tagline: 'Urgent disaster response',
    accent: '#DC2626',
    title: { en: 'Urgent appeal — families need you 🚨', ar: 'نداء عاجل — العائلات بحاجتك 🚨' },
    body: {
      en: 'An emergency has left families without the basics. Every minute counts — donate now to deliver food, water and shelter fast.',
      ar: 'حالة طارئة تركت عائلات دون أساسيات الحياة. كل دقيقة تهمّ — تبرّع الآن لإيصال الطعام والماء والمأوى بسرعة.',
    },
  },
  {
    id: 'thank_you',
    icon: Heart,
    label: 'Thank Donors',
    tagline: 'Donor appreciation',
    accent: '#16A34A',
    title: { en: 'Thank you for your generosity 🙏', ar: 'شكراً لكرمكم 🙏' },
    body: {
      en: 'Because of you, families ate, children learned, and hope returned. Thank you for standing with those in need — your kindness changes lives.',
      ar: 'بفضلكم أكلت عائلات، وتعلّم أطفال، وعادت آمال. شكراً لوقوفكم مع المحتاجين — كرمكم يغيّر الحياة.',
    },
  },
]
