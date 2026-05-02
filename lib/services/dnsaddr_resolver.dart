import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

/// Resolves /dnsaddr/ addresses to concrete multiaddrs by querying DNS TXT records.
/// Filters for TCP-compatible addresses only (required for iOS).
class DnsaddrResolver {
  /// Cloudflare DNS-over-HTTPS endpoint
  static const String _dohEndpoint = 'https://cloudflare-dns.com/dns-query';

  /// Resolves a /dnsaddr/ multiaddr to a list of TCP-compatible addresses.
  /// 
  /// Example input: /dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN
  /// Example output: ['/ip4/104.131.131.82/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN']
  static Future<List<String>> resolve(String dnsaddrMultiaddr) async {
    try {
      // Parse the /dnsaddr/ multiaddr
      final parts = dnsaddrMultiaddr.split('/');
      if (parts.length < 3 || parts[1] != 'dnsaddr') {
        Logger.error('Invalid dnsaddr format: $dnsaddrMultiaddr');
        return [];
      }

      final domain = parts[2];
      final peerIdSuffix = parts.length >= 5 && parts[3] == 'p2p' 
          ? '/p2p/${parts[4]}' 
          : '';

      // Query DNS TXT records for _dnsaddr.<domain>
      final dnsName = '_dnsaddr.$domain';
      Logger.debug('Querying DNS TXT records for: $dnsName');

      final txtRecords = await _queryDnsTxt(dnsName);
      if (txtRecords.isEmpty) {
        Logger.debug('No TXT records found for $dnsName');
        return [];
      }

      // Parse and filter addresses
      final resolvedAddrs = <String>[];
      for (final txt in txtRecords) {
        // TXT records have format: dnsaddr=/ip4/1.2.3.4/tcp/4001/p2p/Qm... or dnsaddr=/dnsaddr/...
        if (!txt.startsWith('dnsaddr=')) continue;
        
        final addr = txt.substring(8); // Remove 'dnsaddr=' prefix
        
        // Recursively resolve nested /dnsaddr/ entries
        if (addr.startsWith('/dnsaddr/')) {
          final nested = await resolve(addr);
          resolvedAddrs.addAll(nested);
          continue;
        }

        // Filter: Only keep TCP-compatible addresses
        if (_isTcpCompatible(addr)) {
          // Add peer ID suffix if present and not already in address
          final fullAddr = addr.contains('/p2p/') ? addr : addr + peerIdSuffix;
          resolvedAddrs.add(fullAddr);
          Logger.debug('Resolved TCP address: $fullAddr');
        } else {
          Logger.debug('Skipping non-TCP address: $addr');
        }
      }

      return resolvedAddrs;
    } catch (e) {
      Logger.error('Error resolving $dnsaddrMultiaddr', e);
      return [];
    }
  }

  /// Resolves multiple /dnsaddr/ multiaddrs in parallel.
  static Future<List<String>> resolveMultiple(List<String> dnsaddrMultiaddrs) async {
    final results = await Future.wait(
      dnsaddrMultiaddrs.map((addr) => resolve(addr)),
    );
    
    // Flatten and deduplicate
    final allAddrs = <String>{};
    for (final addrs in results) {
      allAddrs.addAll(addrs);
    }
    
    return allAddrs.toList();
  }

  /// Queries DNS TXT records using DNS-over-HTTPS (Cloudflare).
  static Future<List<String>> _queryDnsTxt(String domain) async {
    try {
      final uri = Uri.parse(_dohEndpoint).replace(queryParameters: {
        'name': domain,
        'type': 'TXT',
      });

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/dns-json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        Logger.error('DNS query failed with status: ${response.statusCode}');
        return [];
      }

      final data = json.decode(response.body);
      final answers = data['Answer'] as List?;
      
      if (answers == null || answers.isEmpty) {
        return [];
      }

      // Extract TXT record data (format: "\"dnsaddr=/ip4/...\"")
      final txtRecords = <String>[];
      for (final answer in answers) {
        if (answer['type'] == 16) { // TXT record type
          final txtData = answer['data'] as String;
          // Remove surrounding quotes and unescape
          final cleaned = txtData.replaceAll('"', '');
          txtRecords.add(cleaned);
        }
      }

      return txtRecords;
    } catch (e) {
      Logger.error('DNS TXT query error for $domain', e);
      return [];
    }
  }

  /// Checks if a multiaddr is TCP-compatible (required for iOS).
  /// 
  /// iOS libp2p needs TCP on IPv4 (or IPv6). Other transports like QUIC, WebSocket
  /// may not be available or reliable on iOS.
  /// 
  /// IMPORTANT: iOS CAN resolve /dns/hostname addresses via DNS A/AAAA records.
  /// iOS CANNOT resolve /dnsaddr/ addresses via DNS TXT records (that's why we do it ourselves).
  static bool _isTcpCompatible(String multiaddr) {
    // Accept: /ip4/.../tcp/..., /ip6/.../tcp/..., /dns/hostname/tcp/..., /dns4/.../tcp/..., /dns6/.../tcp/...
    // Reject: /ip4/.../udp/..., /quic/..., /ws/..., /wss/...
    
    final hasTcp = multiaddr.contains('/tcp/');
    final hasIpOrDns = multiaddr.contains('/ip4/') || 
                       multiaddr.contains('/ip6/') || 
                       multiaddr.contains('/dns/') || 
                       multiaddr.contains('/dns4/') || 
                       multiaddr.contains('/dns6/');
    
    // Reject explicit non-TCP transports
    final hasQuic = multiaddr.contains('/quic');
    final hasUdp = multiaddr.contains('/udp/');
    final hasWs = multiaddr.contains('/ws/') || multiaddr.contains('/wss/');
    
    return hasIpOrDns && hasTcp && !hasQuic && !hasUdp && !hasWs;
  }

  /// Helper: Resolve bootstrap addresses, splitting direct and /dnsaddr/ entries.
  /// 
  /// Returns a list where /dnsaddr/ addresses are resolved to TCP-compatible peers,
  /// and direct addresses are kept as-is (if TCP-compatible).
  static Future<List<String>> resolveBootstrapPeers(List<String> bootstrapPeers) async {
    final dnsaddrPeers = <String>[];
    final directPeers = <String>[];

    // Split into dnsaddr and direct peers
    for (final peer in bootstrapPeers) {
      if (peer.startsWith('/dnsaddr/')) {
        dnsaddrPeers.add(peer);
      } else if (_isTcpCompatible(peer)) {
        directPeers.add(peer);
      } else {
        Logger.debug('Skipping non-TCP bootstrap peer: $peer');
      }
    }

    // Resolve all /dnsaddr/ peers
    final resolved = dnsaddrPeers.isNotEmpty 
        ? await resolveMultiple(dnsaddrPeers)
        : <String>[];

    // Combine direct + resolved, deduplicate
    final allPeers = <String>{...directPeers, ...resolved};
    
    Logger.info('📋 Bootstrap peers resolved: ${allPeers.length} total (${directPeers.length} direct, ${resolved.length} from dnsaddr)');
    
    return allPeers.toList();
  }
}
