// Pins which pictures the app is allowed to shrink, and which it must not.
//
// WHY THIS FILE EXISTS (E3)
// The client asked for two things in one sentence: constrain the size of
// account images, and leave case documents alone — "لضمان وضوح تفاصيلها عند
// الفحص", so their detail survives inspection. The app was doing neither half.
//
// Neither half, not one: `pickCroppedImage` passed no `maxWidth`/`maxHeight`
// at all, so nothing was ever resized — an 8000px camera shot went up at full
// dimensions. And every attachment took the SAME path as an avatar, so a
// medical report was JPEG-compressed twice on its way to the server (once by
// the picker at quality 85, again by the cropper at 90) while its pixel
// dimensions were left untouched. That is the exact inverse of what was
// asked: the compression that ruins small print was applied, the resizing
// that saves bandwidth was not.
//
// WHAT MAKES THE DEFAULT SAFE
// `fidelityForAttachment` returns `document` for anything it does not
// recognise. Mis-filing a document as an account image destroys detail that
// cannot be recovered; mis-filing an account image as a document costs some
// bytes. Only one of those is reversible, so the unknown case takes the
// reversible one.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/shared/utils/image_pick.dart';

void main() {
  group('the two fidelities differ in exactly the ways that matter', () {
    test('an account image is bounded and compressed', () {
      expect(
        PhotoFidelity.display.maxDimension,
        isNotNull,
        reason: 'this is the "constrain image size" half of E3; a null bound '
            'means no resizing happens at all, which was the original bug',
      );
      expect(PhotoFidelity.display.pickQuality, isNotNull);
      expect(PhotoFidelity.display.cropQuality, isNotNull);
    });

    test('a document is neither', () {
      expect(
        PhotoFidelity.document.maxDimension,
        isNull,
        reason: 'a resized medical report cannot be read at the zoom level '
            'the reviewer needs',
      );
      expect(
        PhotoFidelity.document.pickQuality,
        isNull,
        reason:
            'image_picker returns the original file untouched when quality is '
            'null — 100 still re-encodes, which is not the same thing',
      );
    });
  });

  group('the carve-out covers every category the client named', () {
    // ID and identity papers, ration/residence cards, ownership proof,
    // medical reports, house photos, certificates and CVs. Named as rules
    // rather than as screens because the rule id is what the form carries.
    const documentRules = <String>[
      'recipient_id_photo',
      'recipient_ration_card_photo',
      'recipient_property_proof_photo',
      'recipient_medical_report_photo',
      'recipient_house_facade_photo',
      'recipient_house_inside_photo',
      'recipient_house_outside_photo',
      'volunteer_golden_square_photo',
      'volunteer_id_photo',
      'volunteer_ration_card_photo',
      'volunteer_residence_card_photo',
      'volunteer_passport_photo',
      'volunteer_graduation_cert_photo',
      'volunteer_cv_photo',
    ];

    for (final rule in documentRules) {
      test('$rule keeps its original size and quality', () {
        expect(
          fidelityForAttachment(rule),
          PhotoFidelity.document,
          reason: '$rule is a document the reviewer has to read',
        );
      });
    }

    test('the personal photo is the account image, and is compressed', () {
      expect(
        fidelityForAttachment('recipient_personal_photo'),
        PhotoFidelity.display,
      );
      expect(
        fidelityForAttachment('volunteer_personal_photo'),
        PhotoFidelity.display,
      );
    });

    test('an attachment nobody classified is treated as a document', () {
      expect(
        fidelityForAttachment('some_future_attachment'),
        PhotoFidelity.document,
        reason: 'the unrecoverable mistake is compressing a document, so the '
            'unknown case must fall the other way',
      );
    });
  });
}
