import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/contact.dart';
import '../providers/services_provider.dart';
import '../services/p2p_service.dart';
import '../services/interfaces/i_storage_service.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';
// TODO(coming-soon): re-enable when share-contact feature ships
// import 'contact_qr_share_screen.dart';

class ContactDetailScreen extends ConsumerStatefulWidget {
  final String peerID;

  const ContactDetailScreen({
    super.key,
    required this.peerID,
  });

  @override
  ConsumerState<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen> {
  final _nameController = TextEditingController();
  
  Contact? _contact;
  File? _profileImage;
  bool _loading = true;
  
  P2PService get _p2pService => ref.read(p2pServiceProvider);
  IStorageService get _storageService => ref.read(storageServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadContactData();
  }

  Future<void> _loadContactData() async {
    try {
      final result = await _storageService.getContact(widget.peerID);
      final contact = result.valueOrNull;
      
      if (!mounted) return;
      
      if (contact != null) {
        setState(() {
          _contact = contact;
          _nameController.text = contact.displayName;
          _loading = false;
        });
        
        // Load profile image
        await _loadProfileImage();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      Logger.error('Error loading contact', e);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadProfileImage() async {
    if (_contact?.profileImagePath == null) return;
    
    try {
      File imageFile;
      final imagePath = _contact!.profileImagePath!;
      
      if (imagePath.startsWith('/')) {
        imageFile = File(imagePath);
      } else {
        final appSupportDir = await getApplicationSupportDirectory();
        imageFile = File('${appSupportDir.path}/$imagePath');
      }
      
      if (await imageFile.exists()) {
        if (mounted) {
          setState(() {
            _profileImage = imageFile;
          });
        }
      }
    } catch (e) {
      Logger.warning('Error loading profile image: $e');
    }
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    
    if (newName.isEmpty) {
      showTopNotification(
        context,
        'Name cannot be empty',
        isError: true,
      );
      return;
    }
    
    if (newName == _contact?.displayName) {
      return;
    }
    
    try {
      final result = await _storageService.updateContactProfile(
        widget.peerID,
        displayName: newName,
      );
      
      if (!mounted) return;
      
      if (result.isSuccess) {
        setState(() {
          _contact = _contact?.copyWith(displayName: newName);
        });
        
        // Trigger chat update to notify ChatScreen
        _p2pService.triggerChatUpdate();
        
        showTopNotification(
          context,
          'Name updated successfully',
        );
      } else {
        showTopNotification(
          context,
          'Failed to update name',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotification(
        context,
        'Error updating name: $e',
        isError: true,
      );
    }
  }

  void _editContactName() {
    _nameController.text = _contact?.displayName ?? '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('Edit Contact Name')),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter contact name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            Navigator.pop(context);
            if (value.trim().isNotEmpty) {
              _saveName();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (_nameController.text.trim().isNotEmpty) {
                _saveName();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _cleanChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clean Chat'),
        content: const Text(
          'Are you sure you want to delete all messages with this contact?\n\n'
          'The contact will remain in your list, but all chat history will be permanently deleted.\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Clean'),
          ),
        ],
      ),
    );
    
    if (confirmed != true || !mounted) return;
    
    try {
      // Get all messages for this peer
      final messagesResult = await _storageService.getMessagesForPeer(widget.peerID);
      final messages = messagesResult.valueOrNull ?? [];
      
      // Delete each message
      for (final message in messages) {
        await _storageService.deleteMessage(message.id);
      }
      
      if (!mounted) return;
      
      // Trigger chat update to notify ChatScreen
      _p2pService.triggerChatUpdate();
      
      showTopNotification(
        context,
        'Chat cleaned - ${messages.length} messages deleted',
      );
    } catch (e) {
      if (!mounted) return;
      showTopNotification(
        context,
        'Failed to clean chat: $e',
        isError: true,
      );
    }
  }
  
  Future<void> _blockContact() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block Contact'),
        content: Text(
          'Block ${_contact?.displayName ?? 'this contact'}?\n\n'
          '• They will be notified\n'
          '• Their messages will be rejected\n'
          '• They can\'t see your status\n'
          '• You can unblock later',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    
    if (confirmed != true || !mounted) return;
    
    try {
      await _p2pService.blockContact(widget.peerID);
      await _loadContactData(); // Refresh to show blocked state
      
      if (!mounted) return;
      
      showTopNotification(
        context,
        'Contact blocked',
      );
      
      // Pop with true to signal that contact list should be refreshed
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopNotification(
        context,
        'Failed to block contact: $e',
        isError: true,
      );
    }
  }
  
  Future<void> _unblockContact() async {
    try {
      await _p2pService.unblockContact(widget.peerID);
      await _loadContactData(); // Refresh to show unblocked state
      
      if (!mounted) return;
      
      showTopNotification(
        context,
        'Contact unblocked',
      );
      
      // Pop with true to signal that contact list should be refreshed
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopNotification(
        context,
        'Failed to unblock contact: $e',
        isError: true,
      );
    }
  }

  void _showContactInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contact Information',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'View contact details',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // TODO(coming-soon): Share contact QR — re-enable when feature ships
                    // IconButton(
                    //   onPressed: () { ... ContactQrShareScreen ... },
                    //   icon: const Icon(Icons.qr_code_2),
                    //   tooltip: 'Share QR Code',
                    // ),
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              
              // User Name (Read-only - peer's self-chosen name)
              _buildInfoRow(
                icon: Icons.person,
                label: 'User Name',
                value: _contact!.userName,
                subtitle: 'Peer\'s self-chosen name',
              ),
              
              const Divider(height: 32),
              
              // Peer ID
              _buildInfoRow(
                icon: Icons.fingerprint,
                label: 'Peer ID',
                value: widget.peerID,
                isMonospace: true,
              ),
              
              const Divider(height: 32),
              
              // Added Date
              _buildInfoRow(
                icon: Icons.calendar_today,
                label: 'Added',
                value: DateFormat('d. MMMM yyyy').format(_contact!.addedAt.toLocal()),
              ),
              
              const Divider(height: 32),
              
              // Encryption Status
              Row(
                children: [
                  Icon(
                    _contact!.publicKey != null
                        ? Icons.lock
                        : Icons.lock_open,
                    color: _contact!.publicKey != null
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Encryption',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _contact!.publicKey != null
                              ? 'Active - Messages are encrypted'
                              : 'Pending - Waiting for key exchange',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Block/Unblock Contact
              if (_contact!.isBlocked)
                InkWell(
                  onTap: () {
                    Navigator.pop(context); // Close bottom sheet
                    _unblockContact();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Unblock Contact',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                )
              else
                InkWell(
                  onTap: () {
                    Navigator.pop(context); // Close bottom sheet
                    _blockContact();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Block Contact',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              
              const SizedBox(height: 8),
              
              // Clean Chat
              InkWell(
                onTap: () {
                  Navigator.pop(context); // Close bottom sheet
                  _cleanChat();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Clean Chat',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    bool isMonospace = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey.shade600),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: isMonospace ? 'monospace' : null,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Contact'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    if (_contact == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Contact'),
        ),
        body: const Center(
          child: Text('Contact not found'),
        ),
      );
    }
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          title: InkWell(
            onTap: _editContactName,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _contact!.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 14, color: Colors.grey.shade600),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed: _showContactInfo,
              icon: const Icon(Icons.info_outline),
              tooltip: 'Contact Info',
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instagram-style Profile Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // Profile Image
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: _contact!.isKMNodeContact
                            ? Colors.transparent
                            : Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        backgroundImage: _contact!.isKMNodeContact
                            ? const AssetImage('assets/images/logo.png')
                            : (_profileImage != null ? FileImage(_profileImage!) : null),
                        child: (!_contact!.isKMNodeContact && _profileImage == null)
                            ? Text(
                                _contact!.displayName.isNotEmpty ? _contact!.displayName[0].toUpperCase() : '?',
                                style: TextStyle(
                                  fontSize: 32,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  // Tabs
                  Expanded(
                    child: Column(
                      children: [
                        const TabBar(
                          dividerHeight: 0,
                          labelPadding: EdgeInsets.symmetric(horizontal: 8),
                          labelStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          unselectedLabelStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          tabs: [
                            Tab(text: 'Shared'),
                            Tab(text: 'Assets'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 0.5,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Shared/Assets Content
            Expanded(
              child: TabBarView(
                children: [
                  // Shared Tab
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 80,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No shared media yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Shared photos and files will appear here',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Assets Tab
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 80,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No shared assets',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This contact needs to share their assets with you before they appear here',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
