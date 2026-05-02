import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../utils/logger.dart';

part 'auth_provider.g.dart';

/// Auth Service Provider
/// 
/// Provides AuthService instance
@riverpod
AuthService authService(Ref ref) {
  ref.keepAlive();
  return AuthService();
}

/// Auth State - Verwaltet Authentifizierungsstatus
class AuthState {
  final bool isAuthenticated;
  final bool isEnabled;
  
  AuthState({
    required this.isAuthenticated,
    required this.isEnabled,
  });
  
  AuthState copyWith({
    bool? isAuthenticated,
    bool? isEnabled,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

/// Auth State Provider
@riverpod
class AuthStateProvider extends _$AuthStateProvider {
  @override
  AuthState build() {
    _initAuthState();
    return AuthState(isAuthenticated: false, isEnabled: false);
  }
  
  Future<void> _initAuthState() async {
    final authService = ref.read(authServiceProvider);
    final isEnabled = await authService.isAuthEnabled();
    state = state.copyWith(isEnabled: isEnabled);
    Logger.debug('🔒 Auth state initialized: enabled=$isEnabled');
  }
  
  /// Setzt Authentifizierungsstatus
  void setAuthenticated(bool value) {
    state = state.copyWith(isAuthenticated: value);
    Logger.debug('🔒 Auth state changed: authenticated=$value');
  }
  
  /// Aktualisiert "isEnabled" Status
  Future<void> refreshEnabled() async {
    final authService = ref.read(authServiceProvider);
    final isEnabled = await authService.isAuthEnabled();
    state = state.copyWith(isEnabled: isEnabled);
  }
  
  /// Logout (setzt nur authenticated=false, nicht isEnabled)
  void logout() {
    state = state.copyWith(isAuthenticated: false);
    Logger.debug('🔒 User logged out');
  }
}

/// Convenience provider - Gibt nur isAuthenticated zurück
@riverpod
bool isAuthenticated(Ref ref) {
  return ref.watch(authStateProviderProvider).isAuthenticated;
}

/// Convenience provider - Gibt nur isEnabled zurück
@riverpod
bool isAuthEnabled(Ref ref) {
  return ref.watch(authStateProviderProvider).isEnabled;
}
