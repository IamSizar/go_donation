// Pins that a content page does not print its own name twice.
//
// THE BUG
// عملنا الإنساني rendered «عملنا الإنساني» in the top bar and again as a
// heading immediately beneath it. Two different sources happened to hold the
// same string: the bar draws the translated titleKey, while the body drew
// app_content.title_* from the database.
//
// The data was NOT at fault — the section title was correctly empty, exactly as
// migration 111's backfill convention requires. The screen's own empty-state
// branch already reasoned this way ("the top bar already names the page, so a
// lone repeat of it is a blank sheet with a title on it"); it just never
// applied that reasoning to a page that HAD content.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';

void main() {
  test('a stored heading equal to the page name is not drawn again', () {
    expect(shouldShowStoredHeading('عملنا الإنساني', 'عملنا الإنساني'), isFalse);
  });

  test('incidental whitespace does not defeat the comparison', () {
    expect(shouldShowStoredHeading('  عملنا الإنساني ', 'عملنا الإنساني'), isFalse);
  });

  test('a heading that says something new is still shown', () {
    // Not every page repeats itself. Where an owner has written a real heading,
    // suppressing it would lose content rather than remove duplication.
    expect(shouldShowStoredHeading('كيف نعمل', 'عملنا الإنساني'), isTrue);
  });

  test('an empty heading is not drawn', () {
    expect(shouldShowStoredHeading('', 'عملنا الإنساني'), isFalse);
    expect(shouldShowStoredHeading('   ', 'عملنا الإنساني'), isFalse);
  });
}
