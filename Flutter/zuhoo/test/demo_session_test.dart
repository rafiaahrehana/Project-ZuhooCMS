import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuhoo/core/auth/auth_controller.dart';
import 'package:zuhoo/core/auth/auth_models.dart';
import 'package:zuhoo/core/auth/auth_repository.dart';
import 'package:zuhoo/core/network/api_client.dart';
import 'package:zuhoo/core/network/api_exception.dart';
import 'package:zuhoo/core/providers.dart';
import 'package:zuhoo/core/storage/secure_store.dart';

/// The public read-only demo, which is a normal session in every respect the
/// app can see: an ordinary COMPANY_OWNER, an ordinary token, every screen
/// rendering as usual. The one difference is that the backend refuses its
/// writes — so the flag these tests cover is the only thing standing between
/// a visitor and a save that fails for no visible reason.
void main() {
  late _MemStore store;

  /// The repository shares the container's store, as it does in the app —
  /// `authRepositoryProvider` is built from `secureStoreProvider`. A fake with
  /// its own store would write the token somewhere nothing else can see it,
  /// and the session would look empty the moment anything read it back.
  Future<ProviderContainer> containerWith({
    Future<LoginResponse> Function()? onDemo,
  }) async {
    store = _MemStore();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(store),
        authRepositoryProvider
            .overrideWithValue(_FakeRepo(store, onDemo: onDemo)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('startDemo', () {
    test('signs in and marks the session as a demo', () async {
      final container = await containerWith();
      await container.read(authControllerProvider.future);
      expect(container.read(demoSessionProvider), isFalse);

      final user = await container.read(authControllerProvider.notifier).startDemo();

      expect(user.email, 'demo@dhrubotara.example.com');
      expect(user.isCompanyOwner, isTrue);
      expect(container.read(demoSessionProvider), isTrue);
      expect(store.isDemo, isTrue, reason: 'the flag has to outlive the process');
    });

    test('keeps the session despite there being no refresh token', () async {
      // The endpoint issues none on purpose — when the access token dies the
      // demo is over. Storage must not treat the absence as a failure.
      final container = await containerWith();
      await container.read(authControllerProvider.future);
      await container.read(authControllerProvider.notifier).startDemo();

      expect(store.accessToken, isNotNull);
      expect(store.refreshToken, isNull);
      expect(container.read(authControllerProvider).value, isNotNull);
    });

    test('a demo that survives a restart is still a demo', () async {
      // Nothing in the token says "demo", so a restart that forgot the flag
      // would drop the banner and leave the visitor thinking writes will save.
      final container = await containerWith();
      await container.read(authControllerProvider.future);
      await container.read(authControllerProvider.notifier).startDemo();

      final restored = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          authRepositoryProvider.overrideWithValue(_FakeRepo(store)),
        ],
      );
      addTearDown(restored.dispose);

      await restored.read(authControllerProvider.future);
      expect(restored.read(demoSessionProvider), isTrue);
    });

    test('leaving the demo clears the flag', () async {
      final container = await containerWith();
      await container.read(authControllerProvider.future);
      await container.read(authControllerProvider.notifier).startDemo();

      await container.read(authControllerProvider.notifier).clearSession();

      expect(container.read(demoSessionProvider), isFalse);
      expect(container.read(authControllerProvider).value, isNull);
      // clearSession is also what the HTTP layer calls when a refresh is
      // refused, which — with no refresh token — is exactly how a demo ends.
    });

    test('a refused demo leaves nothing signed in', () async {
      final container = await containerWith(
        onDemo: () => throw const ApiException(
          'The demo is not available right now.',
          statusCode: 404,
        ),
      );
      await container.read(authControllerProvider.future);

      await expectLater(
        container.read(authControllerProvider.notifier).startDemo(),
        throwsA(isA<ApiException>()),
      );

      expect(container.read(demoSessionProvider), isFalse);
      expect(container.read(authControllerProvider).value, isNull);
      expect(store.accessToken, isNull);
    });
  });
}

/// A token the app can actually parse. The restore path reads `exp` out of it
/// and discards a session whose token it cannot read, so a placeholder string
/// would make every restart look like a signed-out one.
String _demoToken({Duration validFor = const Duration(minutes: 45)}) {
  String seg(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000;
  return '${seg({'alg': 'HS256'})}.'
      '${seg({'exp': exp, 'role': 'COMPANY_OWNER', 'companyId': 1})}.signature';
}

class _FakeRepo extends AuthRepository {
  _FakeRepo(this._store, {this.onDemo})
      : super(
          ApiClient(store: _store, onSessionExpired: () async {}),
          _store,
        );

  final _MemStore _store;
  final Future<LoginResponse> Function()? onDemo;

  @override
  Future<LoginResponse> startDemo() async {
    if (onDemo != null) return onDemo!();
    final res = LoginResponse(
      userId: 1,
      firstName: 'Tanvir Ahmed',
      email: 'demo@dhrubotara.example.com',
      role: 'COMPANY_OWNER',
      companyId: 1,
      accessToken: _demoToken(),
      // No refresh token, exactly as DemoSessionController returns.
      refreshToken: null,
    );
    await _store.writeTokens(res.accessToken, res.refreshToken);
    return res;
  }

  @override
  Future<void> logout(String? refreshToken) async {}

  @override
  Future<List<String>> loadPermissions() async => const ['LEAVE_VIEW'];

  @override
  Future<List<String>> loadPermissionCatalog() async => const ['LEAVE_VIEW'];
}

class _MemStore extends SecureStore {
  _MemStore() : super(const FlutterSecureStorage());

  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? user;
  bool isDemo = false;
  List<String> permissions = const [];
  List<String> catalog = const [];

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeTokens(String access, String? refresh) async {
    accessToken = access;
    if (refresh != null) refreshToken = refresh;
  }

  @override
  Future<bool> readIsDemo() async => isDemo;

  @override
  Future<void> writeIsDemo() async => isDemo = true;

  @override
  Future<Map<String, dynamic>?> readUser() async => user;

  @override
  Future<Map<String, dynamic>?> readImpersonation() async => null;

  @override
  Future<void> writeUser(Map<String, dynamic> value) async => user = value;

  @override
  Future<List<String>> readPermissions() async => permissions;

  @override
  Future<List<String>> readPermissionCatalog() async => catalog;

  @override
  Future<void> writePermissions(List<String> codes) async => permissions = codes;

  @override
  Future<void> writePermissionCatalog(List<String> codes) async =>
      catalog = codes;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    user = null;
    isDemo = false;
    permissions = const [];
    catalog = const [];
  }
}
