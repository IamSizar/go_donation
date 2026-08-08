/// Motivational tasks/challenges shown by the "Wheel of Fortune" and "Lucky
/// Coupon" quick actions (client spec — Quick Actions, item #4). Spinning the
/// wheel or scratching the coupon lands on one of these at random.
///
/// EDIT THIS LIST to change what a grantor can land on — each entry is a
/// short, encouraging call-to-action. Every entry needs a matching
/// translation key in app_translations.dart for the other 3 languages
/// (falls back to this English text if missing).
const List<String> motivationalTasks = [
  'Make a donation today',
  'Sponsor a family this month',
  'Share the app with a friend',
  'Check in on your active campaigns',
  'Try a new giving category',
  'Invite someone to volunteer',
  'Leave an encouraging comment',
  'Read today\'s news and activities',
];

/// Short labels shown directly on the Wheel of Fortune slices (same order
/// and length as [motivationalTasks] — index i here is the short form of
/// motivationalTasks[i]). Keep these to 1-3 words so they fit on a slice.
const List<String> motivationalTaskShortLabels = [
  'Donate',
  'Sponsor',
  'Share App',
  'Campaigns',
  'New Category',
  'Invite',
  'Comment',
  'Read News',
];
