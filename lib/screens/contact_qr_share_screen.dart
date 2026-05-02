import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Screen shows QR code for sharing a contact with others
/// 
/// Contains:
/// - Contact's PeerID
/// - Contact's Name
/// - Connected Oasis Node (if available)
class ContactQrShareScreen extends StatelessWidget {
  final String peerID;
  final String contactName;
  final String? connectedNodeMultiaddr;
  final File? profileImage;

  const ContactQrShareScreen({
    super.key,
    required this.peerID,
    required this.contactName,
    this.connectedNodeMultiaddr,
    this.profileImage,
  });

  @override
  Widget build(BuildContext context) {
    // Create QR data in compact JSON format
    final qrData = {
      't': 'oasis_contact',  // type (compact)
      'p': peerID,            // peer_id (compact)
      'n': contactName,       // name (compact)
      if (connectedNodeMultiaddr != null) 'm': connectedNodeMultiaddr,  // node multiaddr (compact)
    };

    final qrString = jsonEncode(qrData);
    
    // Debug: Log QR content
    Logger.debug('📱 Contact QR Code generated:');
    Logger.debug('   PeerID: $peerID');
    Logger.debug('   Name: $contactName');
    Logger.debug('   Node: ${connectedNodeMultiaddr ?? 'NONE'}');
    Logger.debug('   QR JSON: $qrString');

    return Scaffold(
      appBar: AppBar(
        title: Text('Share $contactName'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // QR Code
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Profile Image
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      backgroundImage: profileImage != null ? FileImage(profileImage!) : null,
                      child: profileImage == null
                          ? Text(
                              contactName.isNotEmpty ? contactName[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 40,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    // Contact Name below Profile Image
                    Text(
                      contactName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: qrString,
                        version: QrVersions.auto,
                        size: 280,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Scan to add $contactName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Copy Contact Code Button
            GestureDetector(
              onTap: () async {
                // Encode contact data as Base64
                final base64Data = base64Encode(utf8.encode(qrString));
                
                await Clipboard.setData(ClipboardData(text: base64Data));
                
                if (context.mounted) {
                  showTopNotification(
                    context,
                    'Contact code copied!\nShare it via messenger, then receiver can paste it in "Add Contact".',
                    duration: const Duration(seconds: 3),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.share,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Share Contact Code',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Info text
            Text(
              'Share this QR code or contact code to let others add $contactName to their contacts.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
