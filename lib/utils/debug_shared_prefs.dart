import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';

/// Debug utility to inspect and test SharedPreferences
class DebugSharedPrefs {
  /// Print all keys and values in SharedPreferences
  static Future<void> printAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    Logger.info('🔍 SharedPreferences Debug - Total keys: ${keys.length}');
    Logger.info('=' * 60);
    
    for (final key in keys) {
      final value = prefs.get(key);
      if (value is String && value.length > 100) {
        Logger.info('  $key: <String ${value.length} chars>');
        Logger.debug('    ${value.substring(0, 100)}...');
      } else {
        Logger.info('  $key: $value');
      }
    }
    
    Logger.info('=' * 60);
  }
  
  /// Test if SharedPreferences works by writing and reading a test value
  static Future<bool> test() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const testKey = 'debug_test_key';
      final testValue = 'debug_test_value_${DateTime.now().millisecondsSinceEpoch}';
      
      Logger.info('🧪 Testing SharedPreferences...');
      
      // Write
      final writeResult = await prefs.setString(testKey, testValue);
      Logger.info('  Write result: $writeResult');
      
      // Read
      final readValue = prefs.getString(testKey);
      Logger.info('  Read value: $readValue');
      
      // Verify
      final success = readValue == testValue;
      Logger.info('  Test result: ${success ? "✅ SUCCESS" : "❌ FAILED"}');
      
      // Cleanup
      await prefs.remove(testKey);
      
      return success;
    } catch (e) {
      Logger.error('SharedPreferences test failed: $e');
      return false;
    }
  }
  
  /// Show a debug dialog with SharedPreferences contents
  static Future<void> showDebugDialog(BuildContext context) async {
    await printAll();
    await test();
    
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('SharedPreferences Debug'),
          content: const Text('Check console logs for detailed output'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
}
