import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PIN Pad Widget - Custom Nummernpad für PIN-Eingabe
/// 
/// 3x4 Grid mit Zahlen 0-9, Backspace und optional Check-Button
/// Mit Haptic Feedback und Touch-optimiert
class PinPadWidget extends StatelessWidget {
  final ValueChanged<String> onNumberTap;
  final VoidCallback? onBackspaceTap;
  final VoidCallback? onCheckTap;
  final bool showCheckButton;
  final bool checkEnabled;
  
  const PinPadWidget({
    super.key,
    required this.onNumberTap,
    this.onBackspaceTap,
    this.onCheckTap,
    this.showCheckButton = false,
    this.checkEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: 1 2 3
        _buildRow(context, ['1', '2', '3']),
        const SizedBox(height: 12),
        
        // Row 2: 4 5 6
        _buildRow(context, ['4', '5', '6']),
        const SizedBox(height: 12),
        
        // Row 3: 7 8 9
        _buildRow(context, ['7', '8', '9']),
        const SizedBox(height: 12),
        
        // Row 4: Backspace 0 Check
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Backspace Button
            _PinPadButton(
              onTap: onBackspaceTap,
              child: Icon(
                Icons.backspace_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            
            // 0 Button
            _PinPadButton(
              onTap: () {
                HapticFeedback.lightImpact();
                onNumberTap('0');
              },
              child: Text(
                '0',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            
            // Check or Empty Button
            if (showCheckButton && onCheckTap != null)
              _PinPadButton(
                onTap: checkEnabled ? onCheckTap : null,
                child: Icon(
                  Icons.check,
                  color: checkEnabled 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.onSurface.withOpacity(0.3),
                ),
              )
            else
              const SizedBox(width: 80, height: 80), // Empty space
          ],
        ),
      ],
    );
  }
  
  Widget _buildRow(BuildContext context, List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((number) {
        return _PinPadButton(
          onTap: () {
            HapticFeedback.lightImpact();
            onNumberTap(number);
          },
          child: Text(
            number,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// PIN Pad Button - Einzelner Button im Nummernpad
class _PinPadButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  
  const _PinPadButton({
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap != null 
            ? () {
                HapticFeedback.lightImpact();
                onTap!();
              }
            : null,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
