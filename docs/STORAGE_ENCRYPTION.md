# Storage Encryption

## Overview

All local data stored in Hive is now encrypted at rest using **AES-256 encryption** via `HiveAesCipher`.

## Implementation Details

### Encryption Key Management

- **Key Type**: 256-bit (32 bytes) AES key
- **Key Storage**: Flutter Secure Storage (iOS Keychain / Android KeyStore)
- **Key Generation**: Secure random generation on first app launch
- **Key Persistence**: Stored securely across app sessions

### Encrypted Boxes

The following Hive boxes are encrypted:

1. `messages` - All chat messages (including plaintext content)
2. `contacts` - Contact list with encryption keys
3. `nonces` - Replay protection nonces
4. `calls` - Call history

### Security Benefits

✅ **Data at Rest Protection**: All messages stored on device are encrypted
✅ **Hardware-Backed Security**: Encryption key stored in device secure storage
✅ **Automatic Migration**: Old unencrypted data is automatically migrated
✅ **Transparent**: No changes needed to application logic

## Migration

### Automatic Migration

When the app starts with encryption enabled for the first time:

1. Detects existing unencrypted Hive boxes
2. **Copies all data** from unencrypted to encrypted storage
3. Deletes old unencrypted boxes after successful migration
4. All existing messages, contacts, and history are preserved

**Important**: The first implementation (before this fix) deleted data instead of migrating. If you lost data, see recovery options below.

### Data Recovery Options

If your chats disappeared after the initial encryption update:

**Option 1: iOS/Android Device Backup**
- If you have iCloud Backup (iOS) or Google Backup (Android) from before the update
- Restore your device from backup
- Update to the latest app version (with data-preserving migration)
- Restart the app

**Option 2: Contact Your Peers**
- Messages will re-populate when contacts send new messages
- Request contacts to resend important messages

**Option 3: Start Fresh**
- Contacts will remain after re-adding
- Message history will build up again over time

### Manual Reset (if needed)

Run the reset script to clear all local data:

```bash
dart run reset_backoff.dart
```

## Technical Details

### Code Changes

- Added `HiveAesCipher` to all `Hive.openBox()` calls
- Encryption key managed in `_getOrCreateEncryptionKey()`
- Migration logic in `_migrateFromUnencryptedBoxes()`

### Performance

- Minimal overhead: AES encryption/decryption is hardware-accelerated
- No noticeable impact on message read/write operations

### Key Rotation

The encryption key is generated once and persists. To rotate:

1. Delete the key from Flutter Secure Storage
2. Restart the app (new key will be generated)
3. Old encrypted data will be migrated (deleted)

## Notes

- Encryption protects against device-level access (lost/stolen device, file system access)
- Does not protect against:
  - App memory dumps while running
  - Device compromise with root/jailbreak access
  - Backup extractions if not properly secured
  
For maximum security, users should also enable device encryption and use strong device passcodes.
