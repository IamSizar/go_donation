// A stand-in HttpClient, so a test can decide what the network does.
//
// WHY THIS FILE EXISTS
// package:http talks to dart:io's HttpClient on the VM, so HttpOverrides can
// substitute a fake without the production code needing a seam for testing.
// That matters: adding an injection point purely for tests would have changed
// the shape of the code under test.
//
// It started life inside test/api/failure_signalling_test.dart and moved here
// unchanged when a second suite (the City Guide's filter states, C2) needed
// exactly the same three behaviours. Copying 190 lines of fake would have
// meant two harnesses drifting apart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How a faked request should behave.
enum HttpBehaviour {
  /// The socket never connects — offline, DNS failure, unreachable host.
  networkError,

  /// The server answers, but with a failure status.
  serverError,

  /// A normal, successful response carrying [FakeHttpOverrides.body].
  ok,
}

class FakeHttpOverrides extends HttpOverrides {
  FakeHttpOverrides(this.behaviour, {this.body = '{}'});

  final HttpBehaviour behaviour;
  final String body;

  /// Every non-empty request body that was sent through this fake, in order.
  ///
  /// Added for L2, where the thing under test is not the response at all but
  /// WHAT GETS WRITTEN: /api/profile/privacy-extras carries display_name_mode
  /// alongside the social links, and posting the wrong one publishes a
  /// donor's real name. Asserting on the response could never catch that.
  /// Empty bodies are skipped so a GET does not leave a blank entry between
  /// the writes.
  final List<String> requestBodies = <String>[];

  /// Every URL opened through this fake, in order — GETs included.
  ///
  /// Added for L19, where the body alone cannot catch the bug: the engagement
  /// profile's privacy write is POST /api/marriage/:id/privacy, ownership is
  /// checked inside the UPDATE, and a request carrying the right `hidden` list
  /// to the WRONG id answers 403 rather than saving anything. So the id in the
  /// path is part of what has to be pinned.
  final List<Uri> requestUrls = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClientImpl(this);
}

class _FakeHttpClientImpl implements HttpClient {
  _FakeHttpClientImpl(this.overrides);
  final FakeHttpOverrides overrides;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    // Recorded BEFORE the offline branch: a request the app tried to make is
    // still a request it made, and a test asserting "it never called X" would
    // otherwise pass for the wrong reason when the socket is down.
    overrides.requestUrls.add(url);
    if (overrides.behaviour == HttpBehaviour.networkError) {
      // What an unreachable backend actually looks like to the caller.
      throw const SocketException('Network is unreachable');
    }
    return _FakeRequestImpl(overrides);
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

class _FakeRequestImpl implements HttpClientRequest {
  _FakeRequestImpl(this.overrides);
  final FakeHttpOverrides overrides;

  @override
  final HttpHeaders headers = _FakeHeadersImpl();

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
  Future<HttpClientResponse> close() async => _FakeResponseImpl(overrides);

  @override
  void add(List<int> data) => _record(data);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {
    // http's IOClient pipes the finalized body through here, so this — not
    // `add` — is where a POST body actually arrives.
    await for (final chunk in stream) {
      _record(chunk);
    }
  }

  void _record(List<int> data) {
    if (data.isEmpty) return;
    overrides.requestBodies.add(utf8.decode(data, allowMalformed: true));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponseImpl extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponseImpl(this.overrides);
  final FakeHttpOverrides overrides;

  @override
  int get statusCode =>
      overrides.behaviour == HttpBehaviour.serverError ? 500 : 200;

  @override
  int get contentLength => utf8.encode(overrides.body).length;

  /// Advertises the content type the real server sends.
  ///
  /// This is not decoration. `package:http` picks the response encoding from
  /// the `content-type` charset and falls back to LATIN-1 when there is none,
  /// so a fake with bare headers handed every caller mojibake for any
  /// non-ASCII body — every Arabic and Kurdish string this app renders. It
  /// went unnoticed because no suite had asserted on one until K12's
  /// locale-fallback test, which failed for this and not for the code it was
  /// testing.
  @override
  HttpHeaders get headers => _FakeHeadersImpl(
    initial: {
      'content-type': ['application/json; charset=utf-8'],
    },
  );

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

class _FakeHeadersImpl implements HttpHeaders {
  /// [initial] seeds headers the fake should report without anyone setting
  /// them — used for the response's content type. Request headers are created
  /// bare, exactly as before, so nothing a test asserts about what was SENT
  /// changes.
  _FakeHeadersImpl({Map<String, List<String>>? initial}) {
    if (initial != null) _values.addAll(initial);
  }

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
Future<T> withHttp<T>(
  FakeHttpOverrides overrides,
  Future<T> Function() body,
) {
  return HttpOverrides.runZoned(
    body,
    createHttpClient: overrides.createHttpClient,
  );
}

