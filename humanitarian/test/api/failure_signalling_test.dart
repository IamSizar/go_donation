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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/api/task_api.dart';
import 'package:flutter_application_1/api/wallet_api.dart';

/// How a faked request should behave.
enum _Behaviour {
  /// The socket never connects — offline, DNS failure, unreachable host.
  networkError,

  /// The server answers, but with a failure status.
  serverError,

  /// A normal, successful response carrying [_FakeHttpOverrides.body].
  ok,
}

class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides(this.behaviour, {this.body = '{}'});

  final _Behaviour behaviour;
  final String body;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(this);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.overrides);
  final _FakeHttpOverrides overrides;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (overrides.behaviour == _Behaviour.networkError) {
      // What an unreachable backend actually looks like to the caller.
      throw const SocketException('Network is unreachable');
    }
    return _FakeRequest(overrides);
  }

  // http's IOClient closes its client after each request, so this one really
  // is called — it cannot be left to noSuchMethod.
  @override
  void close({bool force = false}) {}

  // Everything below is unused by these tests. `noSuchMethod` keeps the fake
  // from having to implement the whole of HttpClient, which is large and would
  // bury the three lines above that carry the meaning.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.overrides);
  final _FakeHttpOverrides overrides;

  @override
  final HttpHeaders headers = _FakeHeaders();

  // IOClient.send sets each of these on every request, so they have to be real
  // fields rather than noSuchMethod fallbacks.
  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  bool bufferOutput = true;

  @override
  Encoding encoding = utf8;

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(overrides);

  @override
  void add(List<int> data) {}

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.overrides);
  final _FakeHttpOverrides overrides;

  @override
  int get statusCode =>
      overrides.behaviour == _Behaviour.serverError ? 500 : 200;

  @override
  int get contentLength => utf8.encode(overrides.body).length;

  @override
  HttpHeaders get headers => _FakeHeaders();

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => '';

  @override
  List<Cookie> get cookies => const [];

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([utf8.encode(overrides.body)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  final _values = <String, List<String>>{};

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = ['$value'];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values.putIfAbsent(name.toLowerCase(), () => []).add('$value');

  @override
  String? value(String name) => _values[name.toLowerCase()]?.first;

  @override
  ContentType? get contentType => ContentType.json;

  // IOClient walks the response headers to build its own, so this is reached.
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [body] with every HTTP request faked according to [overrides].
Future<T> _withHttp<T>(
  _FakeHttpOverrides overrides,
  Future<T> Function() body,
) {
  return HttpOverrides.runZoned(
    body,
    createHttpClient: overrides.createHttpClient,
  );
}

void main() {
  group('a failed load throws rather than returning an empty result', () {
    test('fetchWalletBalance throws when the network is unreachable', () async {
      await _withHttp(_FakeHttpOverrides(_Behaviour.networkError), () async {
        // The specific regression: this used to return balanceIQD: 0, which
        // the user could not tell apart from genuinely having no money.
        await expectLater(fetchWalletBalance(), throwsA(isA<Object>()));
      });
    });

    test('fetchWalletBalance throws on a 500', () async {
      await _withHttp(_FakeHttpOverrides(_Behaviour.serverError), () async {
        await expectLater(fetchWalletBalance(), throwsA(isA<Object>()));
      });
    });

    test('fetchWalletTransactions throws on a 500', () async {
      await _withHttp(_FakeHttpOverrides(_Behaviour.serverError), () async {
        await expectLater(fetchWalletTransactions(), throwsA(isA<Object>()));
      });
    });

    test('fetchPaymentMethods throws on a 500', () async {
      await _withHttp(_FakeHttpOverrides(_Behaviour.serverError), () async {
        await expectLater(fetchPaymentMethods(), throwsA(isA<Object>()));
      });
    });

    test('fetchMyTasks throws when the network is unreachable', () async {
      await _withHttp(_FakeHttpOverrides(_Behaviour.networkError), () async {
        await expectLater(fetchMyTasks(), throwsA(isA<Object>()));
      });
    });
  });

  group('a successful-but-empty response is still empty, not an error', () {
    // The other half of the contract, and the easy thing to break while
    // fixing the first half: "the server answered and there is nothing" must
    // stay distinguishable from "we could not ask". Over-throwing here would
    // replace every empty state in the app with an error banner.

    test('an empty wallet ledger returns [] rather than throwing', () async {
      await _withHttp(
        _FakeHttpOverrides(_Behaviour.ok, body: '{"transactions": []}'),
        () async {
          expect(await fetchWalletTransactions(), isEmpty);
        },
      );
    });

    test('a 200 with no transactions key is treated as empty', () async {
      await _withHttp(
        _FakeHttpOverrides(_Behaviour.ok, body: '{"ok": true}'),
        () async {
          expect(await fetchWalletTransactions(), isEmpty);
        },
      );
    });

    test(
      'an empty payment catalogue returns [] rather than throwing',
      () async {
        await _withHttp(
          _FakeHttpOverrides(_Behaviour.ok, body: '{"items": []}'),
          () async {
            expect(await fetchPaymentMethods(), isEmpty);
          },
        );
      },
    );

    test('a real balance is parsed and returned', () async {
      await _withHttp(
        _FakeHttpOverrides(
          _Behaviour.ok,
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
