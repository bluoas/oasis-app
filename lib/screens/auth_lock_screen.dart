import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../widgets/pin_input_dots.dart';
import '../widgets/pin_pad_widget.dart';
import '../utils/logger.dart';

/// Auth Lock Screen - PIN/Passwort Eingabe
/// 
/// Zeigt Eingabemaske für PIN oder Passwort an.
/// Implementiert Rate-Limiting und Fehlerbehandlung.
class AuthLockScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;
  
  const AuthLockScreen({
    super.key,
    required this.onUnlocked,
  });

  @override
  ConsumerState<AuthLockScreen> createState() => _AuthLockScreenState();
}

class _AuthLockScreenState extends ConsumerState<AuthLockScreen> {
  final _passwordController = TextEditingController();
  final _focusNode = FocusNode();
  String _pinInput = '';
  bool _isLoading = false;
  String? _errorMessage;
  String? _authType;
  int _pinLength = 4; // Default: 4 digits
  int? _remainingDelay;
  
  @override
  void initState() {
    super.initState();
    _loadAuthType();
    
    // Auto-focus nach kurzer Verzögerung (nur für Password-Mode)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _authType == 'password') {
        _focusNode.requestFocus();
      }
    });
  }
  
  @override
  void dispose() {
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  Future<void> _loadAuthType() async {
    final authService = ref.read(authServiceProvider);
    final type = await authService.getAuthType();
    final pinLength = await authService.getPinLength();
    if (mounted) {
      setState(() {
        _authType = type;
        _pinLength = pinLength ?? 4; // Default: 4 if not set
      });
    }
  }
  
  Future<void> _handleSubmit() async {
    if (_isLoading) return;
    
    final input = _authType == 'pin' ? _pinInput : _passwordController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your ${_authType == 'pin' ? 'PIN' : 'password'}';
      });
      return;
    }
    
    await _verifyInput(input);
  }
  
  Future<void> _handlePinInput(String digit) async {
    if (_pinInput.length >= _pinLength) return;
    
    setState(() {
      _pinInput += digit;
      _errorMessage = null;
    });
    
    // Auto-submit bei vollständiger PIN (nach kurzem Delay für visuelle Bestätigung)
    if (_pinInput.length == _pinLength) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted && _pinInput.length == _pinLength) {
        await _verifyInput(_pinInput);
      }
    }
  }
  
  Future<void> _verifyInput(String input) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _remainingDelay = null;
    });
    
    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.verifyAuth(input);
      
      if (result.success) {
        // Erfolg!
        Logger.success('✅ Authentication successful');
        ref.read(authStateProviderProvider.notifier).setAuthenticated(true);
        widget.onUnlocked();
      } else {
        // Fehler
        if (result.remainingDelaySeconds != null) {
          // Rate-Limiting aktiv
          setState(() {
            _errorMessage = 'Too many failed attempts';
            _remainingDelay = result.remainingDelaySeconds;
            _isLoading = false;
          });
          _startCountdown();
        } else {
          // Falscher PIN/Passwort
          setState(() {
            _errorMessage = result.error ?? 'Invalid ${_authType == 'pin' ? 'PIN' : 'password'}';
            _isLoading = false;
          });
          
          // Shake animation
          _shakeInput();
          
          // Clear input
          if (_authType == 'pin') {
            setState(() {
              _pinInput = '';
            });
          } else {
            _passwordController.clear();
          }
        }
      }
    } catch (e) {
      Logger.error('Authentication error', e);
      setState(() {
        _errorMessage = 'Authentication error';
        _isLoading = false;
      });
    }
  }
  
  void _startCountdown() {
    if (_remainingDelay == null || _remainingDelay! <= 0) return;
    
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      
      setState(() {
        _remainingDelay = (_remainingDelay ?? 1) - 1;
      });
      
      if (_remainingDelay! > 0) {
        _startCountdown();
      } else {
        setState(() {
          _errorMessage = null;
          _isLoading = false;
        });
      }
    });
  }
  
  void _shakeInput() {
    // Simple shake effect durch Vibration
    HapticFeedback.heavyImpact();
  }
  
  @override
  Widget build(BuildContext context) {
    final isPinMode = _authType == 'pin';
    
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo/Icon
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Title
                  Text(
                    'Oasis Locked',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Subtitle
                  Text(
                    'Enter your ${isPinMode ? 'PIN' : 'password'} to unlock',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Rate-Limiting Warning
                  if (_remainingDelay != null && _remainingDelay! > 0)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.timer,
                            size: 48,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Too many failed attempts',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Please wait ${_remainingDelay} second${_remainingDelay! > 1 ? 's' : ''}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    )
                  else if (isPinMode) ...[
                    // PIN Mode: Dots + PIN Pad
                    PinInputDots(
                      pinLength: _pinInput.length,
                      maxLength: _pinLength,
                      filledColor: Theme.of(context).colorScheme.primary,
                    ),
                    
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 48),
                    
                    PinPadWidget(
                      onNumberTap: (number) {
                        if (!_isLoading) {
                          _handlePinInput(number);
                        }
                      },
                      onBackspaceTap: () {
                        if (_pinInput.isNotEmpty && !_isLoading) {
                          setState(() {
                            _pinInput = _pinInput.substring(0, _pinInput.length - 1);
                          });
                        }
                      },
                    ),
                      ] else ...[
                    // Password Mode: TextField + Button
                    TextField(
                      controller: _passwordController,
                      focusNode: _focusNode,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.password),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        errorText: _errorMessage,
                      ),
                      onSubmitted: (_) => _handleSubmit(),
                      enabled: !_isLoading,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    GestureDetector(
                      onTap: _isLoading ? null : _handleSubmit,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: !_isLoading
                              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: !_isLoading
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                                : Colors.grey.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: _isLoading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Unlock',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
