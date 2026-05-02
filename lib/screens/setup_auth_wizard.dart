import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../widgets/pin_input_dots.dart';
import '../widgets/pin_pad_widget.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Setup Auth Wizard - Modern Setup Flow für App-Lock
/// 
/// 3 Steps:
/// 1. Type Selection (PIN vs Password)
/// 2. Enter PIN/Password
/// 3. Confirm PIN/Password
class SetupAuthWizard extends ConsumerStatefulWidget {
  final bool isChangeMode;
  
  const SetupAuthWizard({
    super.key,
    this.isChangeMode = false,
  });

  @override
  ConsumerState<SetupAuthWizard> createState() => _SetupAuthWizardState();
}

class _SetupAuthWizardState extends ConsumerState<SetupAuthWizard> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  
  // Für Change Mode: Der aktuelle Auth-Type (wird geladen und bleibt unverändert)
  bool _currentAuthIsPinMode = true;
  // Der neue/target Auth-Type (wird im Type Selection Step gesetzt)
  bool _targetIsPinMode = true;
  
  int _pinLength = 4; // Default: 4 digits
  String _currentPin = '';
  String _newPin = '';
  String _confirmPin = '';
  
  String _currentPassword = '';
  String _newPassword = '';
  String _confirmPassword = '';
  
  bool _isLoading = false;
  String? _errorMessage;
  
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    Logger.debug('[WIZARD] initState: isChangeMode=${widget.isChangeMode}');
    if (widget.isChangeMode) {
      _loadCurrentAuthSettings();
    }
  }
  
  Future<void> _loadCurrentAuthSettings() async {
    Logger.debug('[WIZARD] Loading current auth settings...');
    final authService = ref.read(authServiceProvider);
    final authType = await authService.getAuthType();
    final pinLength = await authService.getPinLength();
    
    Logger.debug('[WIZARD] Loaded: authType=$authType, pinLength=$pinLength');
    
    if (mounted) {
      setState(() {
        _currentAuthIsPinMode = authType == 'pin';
        _targetIsPinMode = authType == 'pin'; // Initial = aktueller Type
        _pinLength = pinLength ?? 4;
      });
      Logger.debug('[WIZARD] State updated: currentAuthIsPinMode=$_currentAuthIsPinMode, targetIsPinMode=$_targetIsPinMode, pinLength=$_pinLength');
    }
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
  
  void _nextStep() {
    Logger.debug('[WIZARD] _nextStep() called: currentStep=$_currentStep, targetIsPinMode=$_targetIsPinMode');
    final maxSteps = _getTotalSteps();
    final maxIndex = maxSteps - 1; // Steps sind 0-indexed
    Logger.debug('[WIZARD] Total steps: $maxSteps, max index: $maxIndex');
    
    if (_currentStep < maxIndex) {
      setState(() {
        _currentStep++;
        _errorMessage = null;
      });
      Logger.success('[WIZARD] Moving to step $_currentStep (of $maxIndex)');
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Logger.warning('[WIZARD] Already at final step! currentStep=$_currentStep, maxIndex=$maxIndex');
    }
  }
  
  void _previousStep() {
    if (_currentStep > 0) {
      // Reset inputs wenn wir zu bestimmten Steps zurückgehen
      if (_targetIsPinMode) {
        // Im PIN-Modus:
        // - Von "Enter PIN" zurück zu "PIN Length" → Reset _newPin
        // - Von "Confirm PIN" zurück zu "Enter PIN" → Reset _confirmPin
        if (widget.isChangeMode) {
          // Change Mode: 0=Current, 1=Type, 2=Length, 3=Enter, 4=Confirm
          if (_currentStep == 3) {
            // Von Enter zurück zu Length
            Logger.debug('[WIZARD] Going back from Enter PIN to PIN Length → Reset _newPin');
            setState(() {
              _newPin = '';
            });
          } else if (_currentStep == 4) {
            // Von Confirm zurück zu Enter
            Logger.debug('[WIZARD] Going back from Confirm to Enter → Reset _confirmPin');
            setState(() {
              _confirmPin = '';
            });
          } else if (_currentStep == 1) {
            // Von Type Selection zurück zu Current → Reset current input (use currentAuthIsPinMode!)
            Logger.debug('[WIZARD] Going back from Type to Current → Reset _currentPin');
            setState(() {
              _currentPin = '';
              _errorMessage = null;
            });
          }
        } else {
          // Normal Mode: 0=Type, 1=Length, 2=Enter, 3=Confirm
          if (_currentStep == 2) {
            // Von Enter zurück zu Length
            Logger.debug('[WIZARD] Going back from Enter PIN to PIN Length → Reset _newPin');
            setState(() {
              _newPin = '';
            });
          } else if (_currentStep == 3) {
            // Von Confirm zurück zu Enter
            Logger.debug('[WIZARD] Going back from Confirm to Enter → Reset _confirmPin');
            setState(() {
              _confirmPin = '';
            });
          }
        }
      } else {
        // Im Password-Modus: Von Confirm zurück zu Enter
        if (widget.isChangeMode) {
          // Change Mode: 0=Current, 1=Type, 2=Enter, 3=Confirm
          if (_currentStep == 3) {
            Logger.debug('[WIZARD] Going back from Confirm to Enter → Reset _confirmPassword');
            setState(() {
              _confirmPassword = '';
              _confirmPasswordController.clear();
            });
          } else if (_currentStep == 1) {
            // Von Type Selection zurück zu Current → Reset current input (use currentAuthIsPinMode!)
            Logger.debug('[WIZARD] Going back from Type to Current → Reset _currentPassword');
            setState(() {
              _currentPassword = '';
              _currentPasswordController.clear();
              _errorMessage = null;
            });
          }
        } else {
          // Normal Mode: 0=Type, 1=Enter, 2=Confirm
          if (_currentStep == 2) {
            Logger.debug('[WIZARD] Going back from Confirm to Enter → Reset _confirmPassword');
            setState(() {
              _confirmPassword = '';
              _confirmPasswordController.clear();
            });
          }
        }
      }
      
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
  
  Future<void> _handleComplete() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final authService = ref.read(authServiceProvider);
      bool success;
      
      if (widget.isChangeMode) {
        // Ändern
        success = await authService.changeAuth(
          currentValue: _currentAuthIsPinMode ? _currentPin : _currentPassword,
          newValue: _targetIsPinMode ? _newPin : _newPassword,
          isPin: _targetIsPinMode,
        );
        
        if (!success) {
          setState(() {
            _errorMessage = 'Current ${_currentAuthIsPinMode ? 'PIN' : 'password'} incorrect';
            _isLoading = false;
            _currentStep = 0;
          });
          _pageController.jumpToPage(0);
          return;
        }
      } else {
        // Ersteinrichtung
        success = await authService.enableAuth(
          value: _targetIsPinMode ? _newPin : _newPassword,
          isPin: _targetIsPinMode,
        );
      }
      
      if (success) {
        await ref.read(authStateProviderProvider.notifier).refreshEnabled();
        
        if (mounted) {
          showTopNotification(
            context,
            widget.isChangeMode
                ? '${_targetIsPinMode ? 'PIN' : 'Password'} changed successfully'
                : 'App-Lock enabled',
          );
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to save';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      Logger.error('Error saving auth', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }
  
  /// Verify current PIN/Password before allowing change
  Future<void> _verifyCurrentAuth() async {
    Logger.debug('[VERIFY] Starting verification...');
    final authService = ref.read(authServiceProvider);
    final input = _currentAuthIsPinMode ? _currentPin : _currentPassword;
    
    if (input.isEmpty) {
      Logger.warning('[VERIFY] Input is empty');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final result = await authService.verifyAuth(input);
      Logger.debug('[VERIFY] Result: success=${result.success}, error=${result.error}');
      
      if (!mounted) return;
      
      if (result.success) {
        Logger.success('[VERIFY] Verification successful!');
        setState(() {
          _isLoading = false;
        });
        _nextStep();
      } else {
        // Verification failed
        Logger.warning('[VERIFY] Verification failed: ${result.error}');
        setState(() {
          _errorMessage = result.error ?? 'Incorrect ${_currentAuthIsPinMode ? 'PIN' : 'password'}';
          _isLoading = false;
          // Reset input
          if (_currentAuthIsPinMode) {
            _currentPin = '';
          } else {
            _currentPassword = '';
            _currentPasswordController.clear();
          }
        });
      }
    } catch (e) {
      Logger.error('[VERIFY] Verification error', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Calculate total steps based on mode and type
    final totalSteps = _getTotalSteps();
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isChangeMode ? 'Change App-Lock' : 'Setup App-Lock'),
        centerTitle: true,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: _previousStep,
              )
            : null,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
      ),
      body: Column(
        children: [
          // Progress Indicator
          _buildProgressIndicator(totalSteps),
          
          // PageView
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: _buildPages(),
            ),
          ),
        ],
      ),
    );
  }
  
  int _getTotalSteps() {
    // Normal Mode: Type Selection + (PIN Length) + Enter + Confirm = 3 oder 4 steps
    // Change Mode: Current + Type Selection + (PIN Length) + Enter + Confirm = 4 oder 5 steps
    final total = widget.isChangeMode
        ? (_targetIsPinMode ? 5 : 4)  // +1 für Current Auth Step
        : (_targetIsPinMode ? 4 : 3);
    Logger.debug('[WIZARD] _getTotalSteps: targetIsPinMode=$_targetIsPinMode, isChangeMode=${widget.isChangeMode}, total=$total');
    return total;
  }
  
  List<Widget> _buildPages() {
    final pages = <Widget>[];
    Logger.debug('[WIZARD] _buildPages: currentAuthIsPinMode=$_currentAuthIsPinMode, targetIsPinMode=$_targetIsPinMode, isChangeMode=${widget.isChangeMode}');
    
    if (widget.isChangeMode) {
      pages.add(_buildCurrentAuthStep());
      Logger.debug('[WIZARD] Added: Current Auth Step (index 0)');
      pages.add(_buildTypeSelectionStep());
      Logger.debug('[WIZARD] Added: Type Selection Step (index 1)');
      if (_targetIsPinMode) {
        pages.add(_buildPinLengthSelectionStep());
        Logger.debug('[WIZARD] Added: PIN Length Step (index 2)');
      }
      pages.add(_buildEnterAuthStep());
      Logger.debug('[WIZARD] Added: Enter Auth Step (index ${pages.length - 1})');
      pages.add(_buildConfirmAuthStep());
      Logger.debug('[WIZARD] Added: Confirm Auth Step (index ${pages.length - 1})');
    } else {
      pages.add(_buildTypeSelectionStep());
      Logger.debug('[WIZARD] Added: Type Selection Step (index 0)');
      if (_targetIsPinMode) {
        pages.add(_buildPinLengthSelectionStep());
        Logger.debug('[WIZARD] Added: PIN Length Step (index 1)');
      }
      pages.add(_buildEnterAuthStep());
      Logger.debug('[WIZARD] Added: Enter Auth Step (index ${pages.length - 1})');
      pages.add(_buildConfirmAuthStep());
      Logger.debug('[WIZARD] Added: Confirm Auth Step (index ${pages.length - 1})');
    }
    
    Logger.debug('[WIZARD] Total pages built: ${pages.length}');
    return pages;
  }
  
  Widget _buildProgressIndicator(int totalSteps) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: List.generate(totalSteps, (index) {
          final isActive = index <= _currentStep;
          
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < totalSteps - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
  
  // ==================== STEP 0: Current Auth (Change Mode) ====================
  
  Widget _buildCurrentAuthStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          
          Icon(
            Icons.lock_outline,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          
          const SizedBox(height: 24),
          
          Text(
            'Enter current ${_currentAuthIsPinMode ? 'PIN' : 'password'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 48),
          
          if (_currentAuthIsPinMode) ...[
            PinInputDots(
              pinLength: _currentPin.length,
              maxLength: _pinLength,
              filledColor: Theme.of(context).colorScheme.primary,
            ),
            
            const SizedBox(height: 48),
            
            PinPadWidget(
              onNumberTap: (number) {
                Logger.debug('[CURRENT] onNumberTap: $number, current length: ${_currentPin.length}, target length: $_pinLength');
                if (_currentPin.length < _pinLength) {
                  setState(() {
                    _currentPin += number;
                  });
                  Logger.debug('[CURRENT] PIN updated: length=${_currentPin.length}, target=$_pinLength');
                  
                  // Auto-next bei vollständiger PIN (nach kurzem Delay für visuelle Bestätigung)
                  if (_currentPin.length == _pinLength) {
                    Logger.debug('[CURRENT] PIN COMPLETE! Scheduling auto-verify in 300ms...');
                    Future.delayed(const Duration(milliseconds: 300), () {
                      Logger.debug('[CURRENT] Auto-verify callback executing: mounted=$mounted, length=${_currentPin.length}, target=$_pinLength');
                      if (mounted && _currentPin.length == _pinLength) {
                        Logger.success('[CURRENT] Calling _verifyCurrentAuth()!');
                        _verifyCurrentAuth();
                      } else {
                        Logger.warning('[CURRENT] Auto-verify cancelled: mounted=$mounted, length=${_currentPin.length}');
                      }
                    });
                  }
                } else {
                  Logger.warning('[CURRENT] PIN already at max length!');
                }
              },
              onBackspaceTap: () {
                if (_currentPin.isNotEmpty) {
                  setState(() {
                    _currentPin = _currentPin.substring(0, _currentPin.length - 1);
                  });
                }
              },
            ),
            // Hinweis: Kein Check-Button wegen Auto-Advance
          ] else ...[
            TextField(
              controller: _currentPasswordController,
              obscureText: true,
              onChanged: (value) {
                setState(() {
                  _currentPassword = value;
                });
              },
              decoration: InputDecoration(
                labelText: 'Current Password',
                prefixIcon: const Icon(Icons.password),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) {
                if (_currentPassword.length >= 6) {
                  _verifyCurrentAuth();
                }
              },
            ),
            
            const SizedBox(height: 24),
            
            GestureDetector(
              onTap: _currentPassword.length >= 6 && !_isLoading ? _verifyCurrentAuth : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: _currentPassword.length >= 6
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _currentPassword.length >= 6
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _currentPassword.length >= 6
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                        ),
                ),
              ),
            ),
          ],
          
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          
          const Spacer(),
        ],
      ),
    );
  }
  
  // ==================== STEP 1: Type Selection ====================
  
  Widget _buildTypeSelectionStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          
          Text(
            'Choose Lock Type',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 48),
          
          // PIN Option
          _buildTypeCard(
            icon: Icons.pin,
            title: 'PIN',
            subtitle: '4-6 digits',
            isSelected: _targetIsPinMode,
            onTap: () {
              Logger.debug('[TYPE] PIN selected');
              setState(() {
                _targetIsPinMode = true;
                // Reset alle Inputs wenn Type geändert wird
                _newPin = '';
                _confirmPin = '';
                _newPassword = '';
                _confirmPassword = '';
                _newPasswordController.clear();
                _confirmPasswordController.clear();
                _pinLength = 4; // Reset auf default
              });
              Logger.debug('[TYPE] targetIsPinMode=$_targetIsPinMode, inputs reset, calling _nextStep()');
              _nextStep();
            },
          ),
          
          const SizedBox(height: 16),
          
          // Password Option
          _buildTypeCard(
            icon: Icons.password,
            title: 'Password',
            subtitle: 'Minimum 6 characters',
            isSelected: !_targetIsPinMode,
            onTap: () {
              Logger.debug('[TYPE] Password selected');
              setState(() {
                _targetIsPinMode = false;
                // Reset alle Inputs wenn Type geändert wird
                _newPin = '';
                _confirmPin = '';
                _newPassword = '';
                _confirmPassword = '';
                _newPasswordController.clear();
                _confirmPasswordController.clear();
              });
              Logger.debug('[TYPE] targetIsPinMode=$_targetIsPinMode, inputs reset, calling _nextStep()');
              _nextStep();
            },
          ),
          
          const Spacer(),
        ],
      ),
    );
  }
  
  Widget _buildTypeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.primary,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
  
  // ==================== STEP: PIN Length Selection ====================
  
  Widget _buildPinLengthSelectionStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          
          Icon(
            Icons.pin,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          
          const SizedBox(height: 24),
          
          Text(
            'Choose PIN Length',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            'Select how many digits your PIN should have',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 48),
          
          // 4 Digits Option
          _buildPinLengthCard(
            length: 4,
            title: '4 Digits',
            subtitle: 'Quick and easy',
            isSelected: _pinLength == 4,
            onTap: () {
              Logger.debug('[PIN_LENGTH] 4 digits selected');
              setState(() {
                _pinLength = 4;
                // Reset PIN inputs wenn Länge geändert wird
                _newPin = '';
                _confirmPin = '';
              });
              Logger.debug('[PIN_LENGTH] PIN inputs reset, pinLength=$_pinLength, calling _nextStep()');
              _nextStep();
            },
          ),
          
          const SizedBox(height: 16),
          
          // 6 Digits Option
          _buildPinLengthCard(
            length: 6,
            title: '6 Digits',
            subtitle: 'Maximum security',
            isSelected: _pinLength == 6,
            onTap: () {
              Logger.debug('[PIN_LENGTH] 6 digits selected');
              setState(() {
                _pinLength = 6;
                // Reset PIN inputs wenn Länge geändert wird
                _newPin = '';
                _confirmPin = '';
              });
              Logger.debug('[PIN_LENGTH] PIN inputs reset, pinLength=$_pinLength, calling _nextStep()');
              _nextStep();
            },
          ),
          
          const Spacer(),
        ],
      ),
    );
  }
  
  Widget _buildPinLengthCard({
    required int length,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: List.generate(
                  length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: index < length - 1 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
  
  // ==================== STEP 2: Enter Auth ====================
  
  Widget _buildEnterAuthStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          
          Icon(
            Icons.lock_outline,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          
          const SizedBox(height: 24),
          
          Text(
            'Enter your ${_targetIsPinMode ? 'PIN' : 'password'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 48),
          
          if (_targetIsPinMode) ...[
            PinInputDots(
              pinLength: _newPin.length,
              maxLength: _pinLength,
              filledColor: Theme.of(context).colorScheme.primary,
            ),
            
            const SizedBox(height: 48),
            
            PinPadWidget(
              onNumberTap: (number) {
                Logger.debug('[SETUP] onNumberTap: $number, current length: ${_newPin.length}, target length: $_pinLength');
                if (_newPin.length < _pinLength) {
                  setState(() {
                    _newPin += number;
                  });
                  Logger.debug('[SETUP] PIN updated: length=${_newPin.length}, target=$_pinLength');
                  
                  // Auto-next bei vollständiger PIN (nach kurzem Delay für visuelle Bestätigung)
                  if (_newPin.length == _pinLength) {
                    Logger.debug('[SETUP] PIN COMPLETE! Scheduling auto-advance in 300ms...');
                    Future.delayed(const Duration(milliseconds: 300), () {
                      Logger.debug('[SETUP] Auto-advance callback executing: mounted=$mounted, length=${_newPin.length}, target=$_pinLength');
                      if (mounted && _newPin.length == _pinLength) {
                        Logger.success('[SETUP] Calling _nextStep()!');
                        _nextStep();
                      } else {
                        Logger.warning('[SETUP] Auto-advance cancelled: mounted=$mounted, length=${_newPin.length}');
                      }
                    });
                  }
                } else {
                  Logger.warning('[SETUP] PIN already at max length!');
                }
              },
              onBackspaceTap: () {
                if (_newPin.isNotEmpty) {
                  setState(() {
                    _newPin = _newPin.substring(0, _newPin.length - 1);
                  });
                }
              },
            ),
            // Hinweis: Kein Check-Button wegen Auto-Advance
          ] else ...[
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              onChanged: (value) {
                setState(() {
                  _newPassword = value;
                });
              },
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.password),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                helperText: 'Minimum 6 characters',
              ),
              onSubmitted: (_) {
                if (_newPassword.length >= 6) {
                  _nextStep();
                }
              },
            ),
            
            const SizedBox(height: 24),
            
            GestureDetector(
              onTap: _newPassword.length >= 6 ? _nextStep : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: _newPassword.length >= 6
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _newPassword.length >= 6
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _newPassword.length >= 6
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ],
          
          const Spacer(),
        ],
      ),
    );
  }
  
  // ==================== STEP 3: Confirm Auth ====================
  
  Widget _buildConfirmAuthStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          
          const SizedBox(height: 24),
          
          Text(
            'Confirm your ${_targetIsPinMode ? 'PIN' : 'password'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 48),
          
          if (_targetIsPinMode) ...[
            PinInputDots(
              pinLength: _confirmPin.length,
              maxLength: _pinLength,
              filledColor: Theme.of(context).colorScheme.primary,
            ),
            
            const SizedBox(height: 48),
            
            PinPadWidget(
              onNumberTap: (number) {
                Logger.debug('[CONFIRM] onNumberTap: $number, current length: ${_confirmPin.length}, target length: $_pinLength');
                if (_confirmPin.length < _pinLength) {
                  setState(() {
                    _confirmPin += number;
                    _errorMessage = null;
                  });
                  Logger.debug('[CONFIRM] PIN updated: length=${_confirmPin.length}, newPin length=${_newPin.length}');
                  
                  if (_confirmPin.length == _newPin.length) {
                    Logger.debug('[CONFIRM] PIN length matches! Checking if PINs match...');
                    // Check if match
                    if (_confirmPin == _newPin) {
                      Logger.success('[CONFIRM] PINs MATCH! Scheduling completion in 300ms...');
                      // Match! Complete setup (nach kurzem Delay für visuelle Bestätigung)
                      Future.delayed(const Duration(milliseconds: 300), () {
                        Logger.debug('[CONFIRM] Completion callback executing: mounted=$mounted, match=${_confirmPin == _newPin}');
                        if (mounted && _confirmPin == _newPin) {
                          Logger.success('[CONFIRM] Calling _handleComplete()!');
                          _handleComplete();
                        } else {
                          Logger.warning('[CONFIRM] Completion cancelled');
                        }
                      });
                    } else {
                      Logger.error('[CONFIRM] PINs DO NOT MATCH!');
                      // No match
                      HapticFeedback.heavyImpact();
                      setState(() {
                        _errorMessage = 'PINs do not match';
                        _confirmPin = '';
                      });
                    }
                  }
                } else {
                  Logger.warning('[CONFIRM] PIN already at max length!');
                }
              },
              onBackspaceTap: () {
                if (_confirmPin.isNotEmpty) {
                  setState(() {
                    _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
                    _errorMessage = null;
                  });
                }
              },
            ),
          ] else ...[
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              onChanged: (value) {
                setState(() {
                  _confirmPassword = value;
                  _errorMessage = null;
                });
              },
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: const Icon(Icons.password),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                errorText: _errorMessage,
              ),
              onSubmitted: (_) {
                if (_confirmPassword == _newPassword) {
                  _handleComplete();
                } else {
                  setState(() {
                    _errorMessage = 'Passwords do not match';
                  });
                }
              },
            ),
            
            const SizedBox(height: 24),
            
            GestureDetector(
              onTap: _isLoading || _confirmPassword.length < 6
                  ? null
                  : () {
                      if (_confirmPassword == _newPassword) {
                        _handleComplete();
                      } else {
                        setState(() {
                          _errorMessage = 'Passwords do not match';
                        });
                      }
                    },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: !_isLoading && _confirmPassword.length >= 6
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: !_isLoading && _confirmPassword.length >= 6
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
                          'Complete',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _confirmPassword.length >= 6
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                        ),
                ),
              ),
            ),
          ],
          
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          
          const Spacer(),
        ],
      ),
    );
  }
}
