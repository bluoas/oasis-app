import 'package:flutter/material.dart';

/// PIN Input Dots - Visueller Indikator für PIN-Eingabe
/// 
/// Zeigt gefüllte/leere Kreise basierend auf PIN-Länge
/// Mit smooth Animationen beim Hinzufügen/Entfernen
class PinInputDots extends StatelessWidget {
  final int pinLength;
  final int maxLength;
  final Color filledColor;
  final Color emptyColor;
  final double dotSize;
  final double spacing;
  
  const PinInputDots({
    super.key,
    required this.pinLength,
    this.maxLength = 6,
    Color? filledColor,
    Color? emptyColor,
    this.dotSize = 16,
    this.spacing = 12,
  })  : filledColor = filledColor ?? Colors.blue,
        emptyColor = emptyColor ?? Colors.grey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxLength, (index) {
        final isFilled = index < pinLength;
        
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing / 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? filledColor : null,
              border: isFilled ? null : Border.all(
                color: emptyColor,
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}
