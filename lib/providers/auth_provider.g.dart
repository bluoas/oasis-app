// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$authServiceHash() => r'0a5684445d549c8df602949d11e0f3e971a3623e';

/// Auth Service Provider
///
/// Provides AuthService instance
///
/// Copied from [authService].
@ProviderFor(authService)
final authServiceProvider = AutoDisposeProvider<AuthService>.internal(
  authService,
  name: r'authServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$authServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AuthServiceRef = AutoDisposeProviderRef<AuthService>;
String _$isAuthenticatedHash() => r'28a7ccb0cffc9add7f0dc88bce3dd781c5d69604';

/// Convenience provider - Gibt nur isAuthenticated zurück
///
/// Copied from [isAuthenticated].
@ProviderFor(isAuthenticated)
final isAuthenticatedProvider = AutoDisposeProvider<bool>.internal(
  isAuthenticated,
  name: r'isAuthenticatedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$isAuthenticatedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsAuthenticatedRef = AutoDisposeProviderRef<bool>;
String _$isAuthEnabledHash() => r'26d78deb9cd83cecfa1e8f0986cee8b41a5cfbd5';

/// Convenience provider - Gibt nur isEnabled zurück
///
/// Copied from [isAuthEnabled].
@ProviderFor(isAuthEnabled)
final isAuthEnabledProvider = AutoDisposeProvider<bool>.internal(
  isAuthEnabled,
  name: r'isAuthEnabledProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$isAuthEnabledHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsAuthEnabledRef = AutoDisposeProviderRef<bool>;
String _$authStateProviderHash() => r'8d7c48b4610c0f247d74a1a798415fbe5866b4c2';

/// Auth State Provider
///
/// Copied from [AuthStateProvider].
@ProviderFor(AuthStateProvider)
final authStateProviderProvider =
    AutoDisposeNotifierProvider<AuthStateProvider, AuthState>.internal(
      AuthStateProvider.new,
      name: r'authStateProviderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$authStateProviderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AuthStateProvider = AutoDisposeNotifier<AuthState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
