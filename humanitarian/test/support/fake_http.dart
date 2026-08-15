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

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClientImpl(this);
}

class _FakeHttpClientImpl implements HttpClient {
  _FakeHttpClientImpl(this.overrides);
  final FakeHttpOverrides overrides;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
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
  void add(List<int> data) {}

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {}

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

  @override
  HttpHeaders get headers => _FakeHeadersImpl();

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

