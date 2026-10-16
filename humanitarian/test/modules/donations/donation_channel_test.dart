// R2 #47–55 — the way each payment method (as the dashboard-managed catalogue
// types it) lands on one of the three money pages.
//
// Kept from the old "what kind of donation is this?" step test, which went with
// that screen: the mapping is still what decides which methods the electronic
// page offers and which number the balance-transfer page shows.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/modules/donations/models/donation_channel.dart';

/// The live catalogue's own `method_type` vocabulary, copied from
/// GET /api/payment-methods. If the server grows a sixth, this is where the app
/// finds out.
const _liveMethodTypes = <String>['cash', 'bank', 'card', 'wallet', 'mobile'];

void main() {
  test('every method type the server serves reaches exactly one money page', () {
    // A type that belongs to no page can never be chosen once the list is
    // filtered; one that belongs to two is offered under contradictory
    // headings.
    const pages = [
      DonationChannel.cash,
      DonationChannel.electronic,
      DonationChannel.balanceTransfer,
    ];
    for (final type in _liveMethodTypes) {
      final matched = pages.where((c) => c.acceptsMethodType(type)).toList();
      expect(
        matched.map((c) => c.slug).toList(),
        hasLength(1),
        reason: 'method_type "$type" must land on exactly one page',
      );
    }
  });

  test('in-kind takes no payment method', () {
    expect(DonationChannel.inKind.isMoney, isFalse);
    for (final type in _liveMethodTypes) {
      expect(DonationChannel.inKind.acceptsMethodType(type), isFalse);
    }
  });

  test('only the electronic page offers the app wallet among the three', () {
    expect(DonationChannel.electronic.includesAppWallet, isTrue);
    expect(DonationChannel.cash.includesAppWallet, isFalse);
    expect(DonationChannel.balanceTransfer.includesAppWallet, isFalse);
  });

  test('an unknown method type counts as electronic, never vanishes', () {
    expect(DonationChannel.electronic.acceptsMethodType('crypto'), isTrue);
    expect(DonationChannel.cash.acceptsMethodType('crypto'), isFalse);
  });
}
