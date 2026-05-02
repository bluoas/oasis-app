import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Setup Auth Screen - Einrichtung von PIN/Passwort
/// 
/// Modi:
/// - Setup: Erstmalige Einrichtung (wenn noch nicht aktiviert)
/// - Change: Ändern von bestehendem PIN/Passwort
class SetupAuthScreen extends ConsumerStatefulWidget {
  final bool isChangeMode; // true = Ändern, false = Ersteinrichtung
  
  const SetupAuthScreen({
    super.key,
    this.isChangeMode = false,
  });

  @override
  ConsumerState<SetupAuthScreen> createState() => _SetupAuthScreenState();
}

class _SetupAuthScreenState extends ConsumerState<SetupAuthScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  
  bool _isPinMode = true; // true = PIN, false = Passwort
  bool _isLoading = false;
  String? _currentError;
  String? _newError;
  String? _confirmError;
  
  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }
  
  Future<void> _handleSave() async {
    // Reset errors
    setState(() {
      _currentError = null;
      _newError = null;
      _confirmError = null;
    });
    
    final authService = ref.read(authServiceProvider);
    
    // Validierung
    if (widget.isChangeMode) {
      if (_currentController.text.trim().isEmpty) {
        setState(() {
          _currentError = 'Required';
        });
        return;
      }
    }
    
    final newValue = _newController.text.trim();
    final confirmValue = _confirmController.text.trim();
    
    if (newValue.isEmpty) {
      setState(() {
        _newError = 'Required';
      });
      return;
    }
    
    if (confirmValue.isEmpty) {
      setState(() {
        _confirmError = 'Required';
      });
      return;
    }
    
    // Validiere Format
    if (_isPinMode) {
      if (!RegExp(r'^\d{4,6}$').hasMatch(newValue)) {
        setState(() {
          _newError = 'PIN must be 4-6 digits';
        });
        return;
      }
    } else {
      if (newValue.length < 6) {
        setState(() {
          _newError = 'Password must be at least 6 characters';
        });
        return;
      }
    }
    
    // Prüfe ob Werte übereinstimmen
    if (newValue != confirmValue) {
      setState(() {
        _confirmError = 'Does not match';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      bool success;
      
      if (widget.isChangeMode) {
        // Ändern
        success = await authService.changeAuth(
          currentValue: _currentController.text.trim(),
          newValue: newValue,
          isPin: _isPinMode,
        );
        
        if (!success) {
          setState(() {
            _currentError = 'Current PIN/Password incorrect';
            _isLoading = false;
          });
          return;
        }
      } else {
        // Ersteinrichtung
        success = await authService.enableAuth(
          value: newValue,
          isPin: _isPinMode,
        );
      }
      
      if (success) {
        // Refresh auth state
        await ref.read(authStateProviderProvider.notifier).refreshEnabled();
        
        if (mounted) {
          showTopNotification(
            context,
            widget.isChangeMode
                ? '${_isPinMode ? 'PIN' : 'Password'} changed successfully'
                : 'App-Lock enabled',
          );
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          setState(() {
            _newError = 'Failed to save';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      Logger.error('Error saving auth', e);
      if (mounted) {
        setState(() {
          _newError = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isChangeMode ? 'Change App-Lock' : 'Setup App-Lock'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.isChangeMode
                          ? 'Enter your current ${_isPinMode ? 'PIN' : 'password'}, then choose a new one.'
                          : 'Protect your app with a ${_isPinMode ? 'PIN' : 'password'}. You\'ll need to enter it every time you open the app.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Type Selection (nur bei Ersteinrichtung)
            if (!widget.isChangeMode) ...[
              Text(
                'Lock Type',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('PIN'),
                    icon: Icon(Icons.pin),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Password'),
                    icon: Icon(Icons.password),
                  ),
                ],
                selected: {_isPinMode},
                onSelectionChanged: (Set<bool> newSelection) {
                  setState(() {
                    _isPinMode = newSelection.first;
                    _newController.clear();
                    _confirmController.clear();
                    _newError = null;
                    _confirmError = null;
                  });
                },
              ),
              const SizedBox(height: 32),
            ],
            
            // Current PIN/Password (nur bei Änderung)
            if (widget.isChangeMode) ...[
              Text(
                'Current ${_isPinMode ? 'PIN' : 'Password'}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _currentController,
                obscureText: true,
                keyboardType: _isPinMode 
                    ? TextInputType.number 
                    : TextInputType.text,
                inputFormatters: _isPinMode
                    ? [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ]
                    : null,
                decoration: InputDecoration(
                  labelText: 'Current ${_isPinMode ? 'PIN' : 'Password'}',
                  prefixIcon: Icon(_isPinMode ? Icons.pin : Icons.password),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _currentError,
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            // New PIN/Password
            Text(
              '${widget.isChangeMode ? 'New' : ''} ${_isPinMode ? 'PIN' : 'Password'}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newController,
              obscureText: true,
              keyboardType: _isPinMode 
                  ? TextInputType.number 
                  : TextInputType.text,
              inputFormatters: _isPinMode
                  ? [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ]
                  : null,
              decoration: InputDecoration(
                labelText: _isPinMode ? 'Enter PIN (4-6 digits)' : 'Enter Password (min 6 characters)',
                prefixIcon: Icon(_isPinMode ? Icons.pin : Icons.password),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                errorText: _newError,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Confirm PIN/Password
            Text(
              'Confirm ${_isPinMode ? 'PIN' : 'Password'}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              keyboardType: _isPinMode 
                  ? TextInputType.number 
                  : TextInputType.text,
              inputFormatters: _isPinMode
                  ? [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ]
                  : null,
              decoration: InputDecoration(
                labelText: 'Confirm ${_isPinMode ? 'PIN' : 'Password'}',
                prefixIcon: Icon(_isPinMode ? Icons.pin : Icons.password),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                errorText: _confirmError,
              ),
              onSubmitted: (_) => _handleSave(),
            ),
            
            const SizedBox(height: 32),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        widget.isChangeMode ? 'Change' : 'Enable App-Lock',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
