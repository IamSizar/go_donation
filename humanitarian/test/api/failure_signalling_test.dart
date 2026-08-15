// Pins the contract that these API calls SIGNAL failure rather than returning
// an empty list or a default value.
//
// WHY THIS FILE EXISTS
// Seven functions used to end in `catch (_)` and return `[]` — or, worst of
// all, `WalletBalance(balanceIQD: 0)`. A 500 or an offline device therefore
// reached the UI as a SUCCESSFUL EMPTY RESULT, so the screens' error states
// could never fire and the app told users "you have nothing" when the request
// had simply failed. On the wallet that meant showing a confident, specific
// balance of zero, which is a WRONG number rather than a missing one.
//
// The regression is invisible from the UI side: re-adding a `catch (_)` here
// would make every screen quietly go back to lying, while every widget test
// kept passing. So the contract is pinned at this layer, where the mistake
// would actually be made.
//
// HOW THE FAILURES ARE INJECTED
// package:http talks to dart:io's HttpClient on the VM, so HttpOverrides can
// stand in a fake without the production code needing a seam for testing.
// That matters: adding an injection point purely for tests would have changed
// the shape of the code under test.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/api/case_categories_api.dart';
import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/api/task_api.dart';
import 'package:flutter_application_1/api/wallet_api.dart';

import '../support/fake_http.dart';

void main() {
  group('a failed load throws rather than returning an empty result', () {
    test('fetchWalletBalance throws when the network is unreachable', () async {
      await withHttp(FakeHttpOverrides(HttpBehaviour.networkError), () async {
        // The specific regression: this used to return balanceIQD: 0, which
        // the user could not tell apart from genuinely having no money.
        await expectLater(fetchWalletBalance(), throwsA(isA<Object>()));
      });
    });

    test('fetchWalletBalance throws on a 500', () async {
      await withHttp(FakeHttpOverrides(HttpBehaviour.serverError), () async {
        await expectLater(fetchWalletBalance(), throwsA(isA<Object>()));
      });
    });

    test('fetchWalletTransactions throws on a 500', () async {
      await withHttp(FakeHttpOverrides(HttpBehaviour.serverError), () async {
        await expectLater(fetchWalletTransactions(), throwsA(isA<Object>()));
      });
    });

    test('fetchPaymentMethods throws on a 500', () async {
      await withHttp(FakeHttpOverrides(HttpBehaviour.serverError), () async {
        await expectLater(fetchPaymentMethods(), throwsA(isA<Object>()));
      });
    });

    test('fetchMyTasks throws when the network is unreachable', () async {
      await withHttp(FakeHttpOverrides(HttpBehaviour.networkError), () async {
        await expectLater(fetchMyTasks(), throwsA(isA<Object>()));
      });
    });

    // C2 — the eighth function, missed when the other seven were fixed
    // because its silence came with an argument attached: the categories are
    // "a browse FILTER taxonomy, not the user's data", so an empty row was
    // said to state nothing untrue. That held right up until a heading reading
    // "Browse by category" was placed above the row. A heading over nothing
    // does assert something, and it asserts the wrong thing.
    test('fetchCaseCategories throws when the network is unreachable', () async {
      await withHttp(FakeHttpOverrides(HttpBehaviour.networkError), () async {
        await expectLater(fetchCaseCategories(), throwsA(isA<Object>()));
      });
    });

    test('fetchCaseCategories throws on a 500', () async {
      await withHttp(FakeHttpOverrides(HttpBehaviour.serverError), () async {
        await expectLater(fetchCaseCategories(), throwsA(isA<Object>()));
      });
    });
  });

  group('a successful-but-empty response is still empty, not an error', () {
    // The other half of the contract, and the easy thing to break while
    // fixing the first half: "the server answered and there is nothing" must
    // stay distinguishable from "we could not ask". Over-throwing here would
    // replace every empty state in the app with an error banner.

    test('an empty wallet ledger returns [] rather than throwing', () async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: '{"transactions": []}'),
        () async {
          expect(await fetchWalletTransactions(), isEmpty);
        },
      );
    });

    test('a 200 with no transactions key is treated as empty', () async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: '{"ok": true}'),
        () async {
          expect(await fetchWalletTransactions(), isEmpty);
        },
      );
    });

    test(
      'an empty payment catalogue returns [] rather than throwing',
      () async {
        await withHttp(
          FakeHttpOverrides(HttpBehaviour.ok, body: '{"items": []}'),
          () async {
            expect(await fetchPaymentMethods(), isEmpty);
          },
        );
      },
    );

    test('an empty category taxonomy returns [] rather than throwing', () async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: '{"items": []}'),
        () async {
          expect(await fetchCaseCategories(), isEmpty);
        },
      );
    });

    test('a real balance is parsed and returned', () async {
      await withHttp(
        FakeHttpOverrides(
          HttpBehaviour.ok,
          body: '{"balance_iqd": 25000, "currency": "IQD"}',
        ),
        () async {
          final balance = await fetchWalletBalance();
          expect(balance.balanceIQD, 25000);
          expect(balance.currency, 'IQD');
        },
      );
    });
  });
}
