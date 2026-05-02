import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/contact.dart';
// TODO(coming-soon): re-enable call features when voice call ships
// import '../models/call.dart';
import '../providers/services_provider.dart';
import '../services/interfaces/i_storage_service.dart';
import '../services/p2p_service.dart';
import '../services/network_service.dart';
import '../widgets/loading_state.dart';
import '../widgets/empty_state.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';
import 'contact_detail_screen.dart';
import 'add_contact_screen.dart';
import 'chat_screen.dart';
// TODO(coming-soon): re-enable when voice call ships
// import 'active_call_screen.dart';

/// Screen showing all contacts
class ContactsListScreen extends ConsumerStatefulWidget {
  const ContactsListScreen({super.key});

  @override
  ConsumerState<ContactsListScreen> createState() => _ContactsListScreenState();
}

class _ContactsListScreenState extends ConsumerState<ContactsListScreen> {
  List<Contact> _contacts = [];
  bool _loading = true;
  final Map<String, File?> _profileImageCache = {};

  IStorageService get _storageService => ref.read(storageServiceProvider);
  P2PService get _p2pService => ref.read(p2pServiceProvider);
  NetworkService get _networkService => ref.read(networkServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);

    try {
      // Get contacts for active network only (network separation)
      final activeNetworkId = _networkService.activeNetworkId;
      final result = await _storageService.getContactsForNetwork(activeNetworkId);
      
      if (!mounted) return;

      if (result.isSuccess) {
        final contacts = result.valueOrNull ?? [];
        
        // Sort by name
        contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
        
        setState(() {
          _contacts = contacts;
          _loading = false;
        });

        // Load profile images
        await _loadProfileImages();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      Logger.error('Error loading contacts', e);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadProfileImages() async {
    for (final contact in _contacts) {
      if (contact.profileImagePath != null && contact.profileImagePath!.isNotEmpty) {
        try {
          File imageFile;
          final imagePath = contact.profileImagePath!;

          if (imagePath.startsWith('/')) {
            imageFile = File(imagePath);
          } else {
            final appSupportDir = await getApplicationSupportDirectory();
            imageFile = File('${appSupportDir.path}/$imagePath');
          }

          if (await imageFile.exists()) {
            if (mounted) {
              setState(() {
                _profileImageCache[contact.peerID] = imageFile;
              });
            }
          }
        } catch (e) {
          Logger.warning('Error loading profile image for ${contact.displayName}: $e');
        }
      }
    }
  }

  void _openContactDetail(Contact contact) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ContactDetailScreen(peerID: contact.peerID),
      ),
    ).then((_) {
      // Reload contacts when returning from detail screen
      _loadContacts();
    });
  }

  void _openChat(Contact contact) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          peerID: contact.peerID,
          contactName: contact.displayName,
        ),
      ),
    );
    _loadContacts(); // Refresh after returning
  }

  void _initiateCall(Contact contact) {
    // TODO(coming-soon): voice call feature not yet available
  }

  void _addContact() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddContactScreen(),
      ),
    );

    // Reload if contact was added
    if (result == true) {
      _loadContacts();
    }
  }

  Future<void> _unblockContact(Contact contact) async {
    try {
      await _p2pService.unblockContact(contact.peerID);
      
      if (!mounted) return;
      
      showTopNotification(
        context,
        '${contact.displayName} unblocked',
      );
      
      // Reload contacts to update the lists
      _loadContacts();
    } catch (e) {
      if (!mounted) return;
      showTopNotification(
        context,
        'Failed to unblock contact: $e',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Separate contacts into normal and blocked
    final normalContacts = _contacts.where((c) => !c.isBlocked).toList();
    final blockedContacts = _contacts.where((c) => c.isBlocked).toList();
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Contact Book'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Add Contact',
              onPressed: _addContact,
            ),
          ],
          bottom: const TabBar(
            dividerHeight: 0,
            tabs: [
              Tab(text: 'Contacts'),
              Tab(text: 'Blocked'),
            ],
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
        ),
        body: _loading
            ? const LoadingState(message: 'Loading contacts...')
            : TabBarView(
                children: [
                  // Tab 1: Normal Contacts
                  _buildContactsList(normalContacts, isBlocked: false),
                  // Tab 2: Blocked Contacts
                  _buildContactsList(blockedContacts, isBlocked: true),
                ],
              ),
      ),
    );
  }
  
  Widget _buildContactsList(List<Contact> contacts, {required bool isBlocked}) {
    if (contacts.isEmpty) {
      return EmptyState(
        message: isBlocked ? 'No blocked contacts' : 'No contacts yet',
        subtitle: isBlocked 
            ? 'Blocked contacts will appear here'
            : 'Add a contact to start messaging',
        icon: isBlocked ? Icons.block : Icons.contacts_outlined,
        action: isBlocked 
            ? null 
            : GestureDetector(
                onTap: _addContact,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_add,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Add Contact',
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
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadContacts,
      child: ListView.separated(
        itemCount: contacts.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final contact = contacts[index];
          final profileImage = _profileImageCache[contact.peerID];

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: contact.isKMNodeContact
                  ? Colors.transparent
                  : null,
              backgroundImage: contact.isKMNodeContact
                  ? const AssetImage('assets/images/logo.png')
                  : (profileImage != null
                      ? FileImage(profileImage)
                      : null),
              child: (!contact.isKMNodeContact && profileImage == null)
                  ? Text(
                      contact.displayName.isNotEmpty
                          ? contact.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            title: Text(
              contact.displayName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '@${contact.userName}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            trailing: isBlocked
                ? GestureDetector(
                    onTap: () => _unblockContact(contact),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Unblock',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline),
                        iconSize: 20,
                        color: Theme.of(context).colorScheme.primary,
                        tooltip: 'Chat',
                        onPressed: () => _openChat(contact),
                      ),
                      IconButton(
                        icon: const Icon(Icons.call),
                        iconSize: 20,
                        color: contact.publicKey != null
                            ? Colors.green
                            : Colors.grey,
                        tooltip: contact.publicKey != null
                            ? 'Call'
                            : 'No encryption key',
                        onPressed: contact.publicKey != null
                            ? () => _initiateCall(contact)
                            : null,
                      ),
                    ],
                  ),
            onTap: () => _openContactDetail(contact),
          );
        },
      ),
    );
  }
}
