import 'package:flutter_test/flutter_test.dart';
import '../../lib/config/app_config.dart';

void main() {
  group('AppConfig', () {
    group('Environment', () {
      test('has correct enum values', () {
        expect(Environment.values.length, 3);
        expect(Environment.values, contains(Environment.development));
        expect(Environment.values, contains(Environment.staging));
        expect(Environment.values, contains(Environment.production));
      });
    });

    group('Development Config', () {
      late AppConfig config;

      setUp(() {
        config = AppConfig.development();
      });

      test('has correct environment', () {
        expect(config.environment, Environment.development);
        expect(config.isDevelopment, true);
        expect(config.isStaging, false);
        expect(config.isProduction, false);
      });

      test('bootstrap nodes configuration', () {
        // Bootstrap nodes are currently disabled (empty list)
        expect(config.bootstrapNodes, isEmpty);
      });

      test('has fast polling for quick testing', () {
        expect(
          config.messagePollingInterval,
          equals(const Duration(seconds: 10)),
        );
        expect(
          config.backgroundSyncInterval,
          equals(const Duration(minutes: 5)),
        );
      });

      test('has debug logging enabled', () {
        expect(config.debugLogging, true);
      });

      test('has reasonable cache size', () {
        expect(config.maxCachedMessages, 100);
      });

      test('has reasonable timeouts', () {
        expect(config.connectionTimeout, Duration(seconds: 20));
        expect(config.dhtQueryTimeout, Duration(seconds: 30));
      });
    });

    group('Staging Config', () {
      late AppConfig config;

      setUp(() {
        config = AppConfig.staging();
      });

      test('has correct environment', () {
        expect(config.environment, Environment.staging);
        expect(config.isDevelopment, false);
        expect(config.isStaging, true);
        expect(config.isProduction, false);
      });

      test('bootstrap nodes configuration', () {
        // Bootstrap nodes are currently disabled (empty list)
        expect(config.bootstrapNodes, isEmpty);
      });

      test('has moderate polling intervals', () {
        expect(
          config.messagePollingInterval,
          equals(const Duration(seconds: 60)),
        );
        expect(
          config.backgroundSyncInterval,
          equals(const Duration(minutes: 10)),
        );
      });

      test('has debug logging enabled', () {
        expect(config.debugLogging, true);
      });

      test('discovers Oasis nodes via DHT', () {
        expect(config.initialOasisNodes, isEmpty,
            reason: 'Staging should discover nodes via DHT');
      });
    });

    group('Production Config', () {
      late AppConfig config;

      setUp(() {
        config = AppConfig.production();
      });

      test('has correct environment', () {
        expect(config.environment, Environment.production);
        expect(config.isDevelopment, false);
        expect(config.isStaging, false);
        expect(config.isProduction, true);
      });

      test('bootstrap nodes configuration', () {
        // Bootstrap nodes are currently disabled (empty list)
        expect(config.bootstrapNodes, isEmpty);
      });

      test('has conservative polling for battery life', () {
        expect(
          config.messagePollingInterval,
          equals(const Duration(seconds: 10)),
        );
        expect(
          config.backgroundSyncInterval,
          equals(const Duration(minutes: 5)),
        );
      });

      test('has debug logging disabled', () {
        expect(config.debugLogging, false);
      });

      test('has larger cache for better performance', () {
        expect(config.maxCachedMessages, 500);
      });

      test('discovers Oasis nodes via DHT only', () {
        expect(config.initialOasisNodes, isEmpty,
            reason: 'Production should use pure DHT discovery');
      });
    });

    group('Config Comparison', () {
      test('staging has slowest polling intervals', () {
        final dev = AppConfig.development();
        final staging = AppConfig.staging();
        final prod = AppConfig.production();

        // Development and Production have same fast polling (10s, 5min)
        expect(dev.messagePollingInterval, prod.messagePollingInterval);
        expect(dev.backgroundSyncInterval, prod.backgroundSyncInterval);
        
        // Staging is slowest (60s, 10min)
        expect(staging.messagePollingInterval > dev.messagePollingInterval, true);
        expect(staging.backgroundSyncInterval > dev.backgroundSyncInterval, true);
      });

      test('production has largest cache', () {
        final dev = AppConfig.development();
        final staging = AppConfig.staging();
        final prod = AppConfig.production();

        expect(dev.maxCachedMessages < staging.maxCachedMessages, true);
        expect(staging.maxCachedMessages < prod.maxCachedMessages, true);
      });

      test('only production has debug logging disabled', () {
        expect(AppConfig.development().debugLogging, true);
        expect(AppConfig.staging().debugLogging, true);
        expect(AppConfig.production().debugLogging, false);
      });
    });

    group('toString', () {
      test('provides useful debug information', () {
        final config = AppConfig.development();
        final str = config.toString();

        expect(str, contains('development'));
        expect(str, contains('bootstrapNodes'));
        expect(str, contains('polling'));
        expect(str, contains('debug'));
      });
    });

    group('Immutability', () {
      test('config values are const', () {
        final config1 = AppConfig.development();
        final config2 = AppConfig.development();

        // Factory methods should return equivalent configs
        expect(config1.environment, config2.environment);
        expect(config1.messagePollingInterval, config2.messagePollingInterval);
        expect(config1.debugLogging, config2.debugLogging);
      });
    });
  });
}
