import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import '../models/call.dart';
import '../models/contact.dart';
import '../utils/logger.dart';
import '../utils/notification_utils.dart';
import 'interfaces/i_p2p_repository.dart';
import 'interfaces/i_identity_service.dart';
import 'interfaces/i_storage_service.dart';

/// Call Service - Manages WebRTC voice/video calls
/// 
/// Features:
/// - Audio-only calls (Phase 1)
/// - WebRTC peer connections
/// - Signaling via P2P (libp2p streams)
/// - NAT traversal (STUN/ICE)
/// 
/// Architecture:
/// 1. Caller creates offer (SDP)
/// 2. Offer sent via P2P to callee
/// 3. Callee creates answer (SDP)
/// 4. Answer sent back via P2P
/// 5. ICE candidates exchanged
/// 6. WebRTC direct connection established
class CallService {
  // ignore: unused_field
  final IP2PRepository _p2pRepository; // Will be used for P2P signaling integration
  final IIdentityService _identity; // For signing call signals
  final IStorageService _storage; // For persisting call history
  final Uuid _uuid;
  final String? Function()? getActiveNode; // Callback to get active Bootstrap/Oasis Node
  final Stream<Map<String, dynamic>>? callSignalStream; // Stream for incoming call signals
  final Future<void> Function()? triggerMessagePoll; // Callback to manually trigger message polling
  final void Function()? enableFastPolling; // Enable 1s polling for fast call signaling
  final void Function()? disableFastPolling; // Disable fast polling (return to 10s)

  // Current active call
  Call? _currentCall;
  Call? get currentCall => _currentCall;

  // WebRTC Peer Connection
  RTCPeerConnection? _peerConnection;
  
  // Local audio stream
  MediaStream? _localStream;
  
  // Remote audio stream
  MediaStream? _remoteStream;
  
  // Call state stream
  final _callStateController = StreamController<Call?>.broadcast();
  Stream<Call?> get callStateStream => _callStateController.stream;
  
  // Remote stream for UI
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  
  // Call signal subscription
  StreamSubscription<Map<String, dynamic>>? _callSignalSubscription;
  
  // Buffer for ICE candidates that arrive before peer connection is ready
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  
  // Call timer
  Timer? _callTimer;
  DateTime? _callStartTime;
  
  // ICE gathering polling timer
  Timer? _iceGatheringTimer;
  int _iceGatheringPollCount = 0;
  
  // Call timeout timer (auto-end if stuck)
  Timer? _callTimeoutTimer;
  
  // Cleanup guard to prevent multiple cleanup calls
  bool _isCleaningUp = false;
  
  // Track if PeerConnection was actually created (to know if audio session needs reset)
  bool _hadActivePeerConnection = false;
  
  // Track if remote description has been set (needed for ICE candidate buffering)
  bool _hasRemoteDescription = false;
  
  // Ringtone player for incoming/outgoing calls
  AudioPlayer? _ringtonePlayer;
  bool _isRingtonePlaying = false;
  
  // ICE Candidate Queue - prevents concurrent stream congestion under NAT
  // Sending multiple ICE candidates in parallel can exhaust libp2p stream limits
  final List<_QueuedIceCandidate> _iceCandidateQueue = [];
  Timer? _iceCandidateQueueWorker;
  bool _isProcessingIceQueue = false;
  
  // ICE Configuration (STUN servers for NAT traversal)
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  // Media constraints (audio-only for Phase 1)
  final Map<String, dynamic> _mediaConstraints = {
    'audio': true,
    'video': false,
  };

  CallService({
    required IP2PRepository p2pRepository,
    required IIdentityService identity,
    required IStorageService storage,
    this.getActiveNode,
    this.callSignalStream,
    this.triggerMessagePoll,
    this.enableFastPolling,
    this.disableFastPolling,
    Uuid? uuid,
  })  : _p2pRepository = p2pRepository,
        _identity = identity,
        _storage = storage,
        _uuid = uuid ?? const Uuid();

  /// Initialize WebRTC
  Future<void> initialize() async {
    Logger.info('📞 Initializing CallService...');
    
    // Subscribe to incoming call signals
    if (callSignalStream != null) {
      _callSignalSubscription = callSignalStream!.listen((signalData) {
        Logger.debug('📞 Received call signal: ${signalData['signal_type']}');
        _handleIncomingCallSignal(signalData);
      });
      Logger.info('✅ Subscribed to call signal stream');
    }
  }

  /// Handle incoming call signal from P2P stream
  Future<void> _handleIncomingCallSignal(Map<String, dynamic> signalData) async {
    try {
      Logger.debug('📞 _handleIncomingCallSignal called with: $signalData');
      
      final signalType = signalData['signal_type'] as String?;
      final data = signalData['data'] as Map<String, dynamic>?;
      final senderPeerID = signalData['sender'] as String?;
      
      Logger.debug('   Extracted: type=$signalType, sender=$senderPeerID, data=$data');
      
      if (signalType == null || data == null || senderPeerID == null) {
        Logger.error('Invalid call signal: missing required fields');
        return;
      }
      
      // For contact name, we'll use a shortened PeerID as fallback
      // The actual contact name will be resolved from the contacts database
      final contactName = 'User ${senderPeerID.substring(0, 8)}';
      
      Logger.debug('📞 Forwarding to handleIncomingSignal: type=$signalType, contact=$contactName');
      
      // Forward to the existing handleIncomingSignal method
      await handleIncomingSignal(
        contactId: senderPeerID,
        contactName: contactName,
        signalType: signalType,
        data: data,
      );
    } catch (e) {
      Logger.error('Failed to handle incoming call signal: $e');
    }
  }

  /// Initiate an outgoing call
  Future<void> initiateCall({
    required Contact contact,
    CallType type = CallType.audio,
  }) async {
    try {
      Logger.info('📞 Initiating ${type.displayName} to ${contact.displayName}...');

      // Check if already in a call
      if (_currentCall != null) {
        throw Exception('Already in a call');
      }

      // Create call object
      _currentCall = Call.outgoing(
        id: _uuid.v4(),
        contactId: contact.peerID,
        contactName: contact.displayName,
        type: type,
        connectedNodeMultiaddr: contact.connectedNodeMultiaddr,
      );
      _notifyCallState();
      
      // Enable fast polling for quick call signaling
      enableFastPolling?.call();

      // Create peer connection
      await _createPeerConnection();
      
      // GUARD: Check if call was ended while creating peer connection
      if (_currentCall?.state.isEnded ?? true) {
        Logger.warning('⚠️ Call ended while creating peer connection, aborting initiate');
        await _cleanup();
        return;
      }

      // Add local audio stream
      await _addLocalStream();
      
      // GUARD: Check if call was ended while adding local stream
      if (_currentCall?.state.isEnded ?? true) {
        Logger.warning('⚠️ Call ended while adding local stream, aborting initiate');
        await _cleanup();
        return;
      }

      // Create offer  
      final offer = await _peerConnection!.createOffer();
      Logger.debug('📞 Created Offer, setting local description to trigger ICE gathering...');
      await _peerConnection!.setLocalDescription(offer);
      Logger.debug('📞 Local description set, ICE gathering should now be active');
      
      // GUARD: Check if call was ended while creating offer
      Logger.debug('🔍 DEBUG: Guard check - _currentCall: ${_currentCall != null ? "not null" : "NULL"}, state: ${_currentCall?.state}, isEnded: ${_currentCall?.state.isEnded}');
      if (_currentCall?.state.isEnded ?? true) {
        Logger.warning('⚠️ Call ended while creating offer, aborting initiate');
        await _cleanup();
        return;
      }

      Logger.debug('📞 ✅ Guard passed, updating call state to ringing...');
      
      // Update call with local SDP
      _currentCall = _currentCall!.copyWith(
        localSDP: offer.sdp,
        state: CallState.ringing,
      );
      _notifyCallState();
      
      Logger.debug('📞 Starting ringtone...');
      // Start ringtone for outgoing call (unawaited to not block OFFER sending)
      // Ringtone plays in background while we immediately send the offer
      _startRingtone(isIncoming: false).catchError((e) {
        Logger.warning('⚠️ Ringtone failed to start: $e (call continues)');
      });
      
      Logger.debug('📞 Ringtone starting in background, sending offer now...');

      // Send offer to remote peer via P2P
      // Use contact's own node if available, otherwise use active bootstrap node
      final nodeMultiaddr = _currentCall!.connectedNodeMultiaddr ?? getActiveNode?.call();
      if (nodeMultiaddr == null) {
        throw Exception('No Oasis Node available for call signaling');
      }
      final nodePeerID = _extractPeerID(nodeMultiaddr);
      
      Logger.info('📤 Sending call offer to ${contact.displayName}...');
      await _sendCallSignal(
        contactId: contact.peerID,
        nodePeerID: nodePeerID,
        signalType: 'offer',
        data: {
          'callId': _currentCall!.id,
          'type': type.name,
          'sdp': offer.sdp,
        },
      );

      Logger.info('✅ Call offer sent to ${contact.displayName}');
      
      // Start call timeout timer (auto-end if no answer after 120s)
      _startCallTimeoutTimer();
      
      // Start rapid polling to get Answer and ICE candidates quickly
      _startICEGatheringPolls();
    } catch (e) {
      Logger.error('❌ Failed to initiate call: $e');
      await endCall();
      rethrow;
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall(Call incomingCall) async {
    try {
      Logger.info('📞 Accepting call from ${incomingCall.contactName}...');

      _currentCall = incomingCall.copyWith(state: CallState.connecting);
      _notifyCallState();
      
      // Enable fast polling for quick call signaling
      enableFastPolling?.call();

      // Create peer connection
      await _createPeerConnection();
      
      // GUARD: Check if call was ended while creating peer connection
      if (_currentCall?.state.isEnded ?? true) {
        Logger.warning('⚠️ Call ended while creating peer connection, aborting accept');
        await _cleanup();
        return;
      }

      // Add local audio stream
      await _addLocalStream();
      
      // GUARD: Check if call was ended while adding local stream
      if (_currentCall?.state.isEnded ?? true) {
        Logger.warning('⚠️ Call ended while adding local stream, aborting accept');
        await _cleanup();
        return;
      }

      // Set remote description (offer) - MUST be set before ICE candidates can be added
      if (incomingCall.remoteSDP != null) {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(incomingCall.remoteSDP!, 'offer'),
        );
        _hasRemoteDescription = true;
        Logger.debug('📞 Remote description (offer) set');
      }
      
      // GUARD: Check if call was ended while setting remote description
      if (_currentCall?.state.isEnded ?? true) {
        Logger.warning('⚠️ Call ended while setting remote description, aborting accept');
        await _cleanup();
        return;
      }

      // Create answer
      final answer = await _peerConnection!.createAnswer();
      Logger.debug('📞 Created Answer, setting local description to trigger ICE gathering...');
      await _peerConnection!.setLocalDescription(answer);
      Logger.debug('📞 Local description set, ICE gathering should now be active');
      
      // GUARD: Check if call was ended while creating answer
      if (_currentCall?.state.isEnded ?? true) {
        Logger.warning('⚠️ Call ended while creating answer, aborting accept');
        Logger.info('🛡️ Race condition prevented: caller canceled while callee was accepting');
        await _cleanup();
        return;
      }
      
      // Apply any ICE candidates that arrived before peer connection was ready
      // (after remote description is set, as required by WebRTC)
      await _drainPendingIceCandidates();

      // Stop ringtone when accepting call
      await _stopRingtone();

      // Update call with local SDP - keep state as CONNECTING until WebRTC connects
      _currentCall = _currentCall!.copyWith(
        localSDP: answer.sdp,
        state: CallState.connecting, // Stay in connecting until WebRTC connection is established
      );
      _notifyCallState();

      // Send answer to remote peer via P2P
      final nodeMultiaddr = incomingCall.connectedNodeMultiaddr ?? getActiveNode?.call();
      if (nodeMultiaddr == null) {
        throw Exception('No Oasis Node available for call signaling');
      }
      final nodePeerID = _extractPeerID(nodeMultiaddr);
      
      Logger.info('📤 Sending answer to caller...');
      await _sendCallSignal(
        contactId: incomingCall.contactId,
        nodePeerID: nodePeerID,
        signalType: 'answer',
        data: {
          'callId': incomingCall.id,
          'sdp': answer.sdp,
        },
      );

      // DO NOT start call timer here - it will start when WebRTC connection is established
      // in the onConnectionState callback
      
      // Enable speaker automatically for voice calls
      await _enableSpeaker();

      Logger.info('✅ Call accepted and answer sent');
      
      // Start call timeout timer (auto-end if WebRTC doesn't connect within 120s)
      _startCallTimeoutTimer();
      
      // Start rapid polling to get ICE candidates quickly
      _startICEGatheringPolls();
    } catch (e) {
      Logger.error('❌ Failed to accept call: $e');
      await endCall();
      rethrow;
    }
  }

  /// Reject an incoming call
  Future<void> rejectCall(Call incomingCall) async {
    try {
      Logger.info('📞 Rejecting call from ${incomingCall.contactName}...');

      // Send reject signal
      final nodeMultiaddr = incomingCall.connectedNodeMultiaddr ?? getActiveNode?.call();
      if (nodeMultiaddr == null) {
        throw Exception('No Oasis Node available for call signaling');
      }
      final nodePeerID = _extractPeerID(nodeMultiaddr);
      
      await _sendCallSignal(
        contactId: incomingCall.contactId,
        nodePeerID: nodePeerID,
        signalType: 'reject',
        data: {
          'callId': incomingCall.id,
        },
      );

      _currentCall = incomingCall.copyWith(state: CallState.rejected);
      _notifyCallState();
      await _saveCallToHistory(); // Save when call is rejected

      // Play end call tone for user feedback
      await NotificationUtils.playCallEndTone();

      // CRITICAL: Cleanup resources and stop ringtone
      await _cleanup();

      // Clear after delay - GUARD: Check call ID to prevent race condition
      final callIdToRemove = incomingCall.id;
      Future.delayed(const Duration(seconds: 2), () {
        if (_currentCall?.id == callIdToRemove && _currentCall?.state == CallState.rejected) {
          Logger.debug('🧹 Clearing rejected call $callIdToRemove from state');
          _currentCall = null;
          _notifyCallState();
        }
      });
    } catch (e) {
      Logger.error('❌ Failed to reject call: $e');
      // Ensure cleanup even on error to stop ringtone
      await _cleanup();
    }
  }

  /// End the current call
  Future<void> endCall() async {
    try {
      Logger.info('📞 Ending call...');

      if (_currentCall != null) {
        // Send end signal to remote peer
        final nodeMultiaddr = _currentCall!.connectedNodeMultiaddr ?? getActiveNode?.call();
        if (nodeMultiaddr != null) {
          final nodePeerID = _extractPeerID(nodeMultiaddr);
          await _sendCallSignal(
            contactId: _currentCall!.contactId,
            nodePeerID: nodePeerID,
            signalType: 'end',
            data: {
              'callId': _currentCall!.id,
            },
          );
        }

        _currentCall = _currentCall!.copyWith(
          state: CallState.ended,
          duration: _callStartTime != null
              ? DateTime.now().difference(_callStartTime!)
              : null,
        );
        _notifyCallState();
        await _saveCallToHistory(); // Save when call ends
      }

      // Play end call tone
      await NotificationUtils.playCallEndTone();

      // Disable fast polling - return to battery-friendly interval
      disableFastPolling?.call();
      
      // Cleanup
      await _cleanup();

      // Clear after delay - GUARD: Check call ID to prevent race condition
      final callIdToRemove = _currentCall?.id;
      Future.delayed(const Duration(seconds: 2), () {
        if (callIdToRemove != null && _currentCall?.id == callIdToRemove && _currentCall?.state == CallState.ended) {
          Logger.debug('🧹 Clearing ended call $callIdToRemove from state');
          _currentCall = null;
          _notifyCallState();
        }
      });
    } catch (e) {
      Logger.error('❌ Failed to end call: $e');
    }
  }

  /// Toggle mute
  Future<void> toggleMute() async {
    if (_currentCall == null || _localStream == null) return;

    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      final newMuteState = !_currentCall!.isMuted;
      audioTracks.first.enabled = !newMuteState;

      _currentCall = _currentCall!.copyWith(isMuted: newMuteState);
      _notifyCallState();

      Logger.debug('🔇 Mute: $newMuteState');
    }
  }

  /// Toggle speaker
  Future<void> toggleSpeaker() async {
    if (_currentCall == null) return;

    final newSpeakerState = !_currentCall!.isSpeakerOn;
    
    // Enable/disable speakerphone via flutter_webrtc
    try {
      await Helper.setSpeakerphoneOn(newSpeakerState);
      Logger.debug('🔊 Speaker hardware updated: $newSpeakerState');
    } catch (e) {
      Logger.error('❌ Failed to toggle speaker: $e');
    }

    _currentCall = _currentCall!.copyWith(isSpeakerOn: newSpeakerState);
    _notifyCallState();

    Logger.debug('🔊 Speaker state: $newSpeakerState');
  }
  
  /// Enable speaker (called automatically when call connects)
  Future<void> _enableSpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(true);
      if (_currentCall != null) {
        _currentCall = _currentCall!.copyWith(isSpeakerOn: true);
        _notifyCallState();
      }
      Logger.info('🔊 Speaker enabled automatically');
    } catch (e) {
      Logger.error('❌ Failed to enable speaker: $e');
    }
  }

  /// Handle incoming call signal
  Future<void> handleIncomingSignal({
    required String contactId,
    required String contactName,
    required String signalType,
    required Map<String, dynamic> data,
  }) async {
    try {
      Logger.debug('📞 Received signal: $signalType from $contactName');

      switch (signalType) {
        case 'offer':
          // Incoming call
          Logger.info('📞 Received "offer" signal from $contactName (callId: ${data['callId']})');
          
          // GUARD: Check if we already have an active call
          if (_currentCall != null && !_currentCall!.state.isEnded) {
            Logger.warning('⚠️ Ignoring incoming call - already in call (state: ${_currentCall!.state})');
            
            // Send busy signal to caller
            try {
              final activeNode = getActiveNode?.call();
              if (activeNode != null) {
                final nodePeerID = _extractPeerID(activeNode);
                await _sendCallSignal(
                  contactId: contactId,
                  nodePeerID: nodePeerID,
                  signalType: 'busy',
                  data: {'callId': data['callId'] as String},
                );
                Logger.info('📞 Sent busy signal to $contactName');
              }
            } catch (e) {
              Logger.error('❌ Failed to send busy signal: $e');
            }
            break;
          }
          
          final callType = CallType.values.firstWhere(
            (e) => e.name == data['type'],
            orElse: () => CallType.audio,
          );

          // Get active node for sending answer back
          final activeNode = getActiveNode?.call();

          _currentCall = Call.incoming(
            id: data['callId'] as String,
            contactId: contactId,
            contactName: contactName,
            type: callType,
            remoteSDP: data['sdp'] as String?,
            connectedNodeMultiaddr: activeNode, // Use our active node to send answer
          );
          _notifyCallState();
          
          // Enable fast polling for quick call signaling (even before accepting)
          // This ensures ANSWER and ICE candidates are exchanged quickly
          enableFastPolling?.call();
          
          Logger.info('📞 Incoming call from $contactName, showing incoming call screen');
          
          // Start ringtone for incoming call
          await _startRingtone(isIncoming: true);
          break;

        case 'answer':
          // Call answered by remote
          Logger.info('📞 Received "answer" signal (callId: ${data['callId']}, current: ${_currentCall?.id}, state: ${_currentCall?.state})');
          
          // CRITICAL GUARD: Only process answer if we're in the correct state
          // This prevents race condition where:
          // 1. Caller cancels call while ringing
          // 2. At same time, callee accepts call
          // 3. Caller receives "answer" signal AFTER already canceling
          // 4. Without this guard, WebRTC would be established even though caller canceled
          if (_currentCall == null) {
            Logger.warning('⚠️ Ignoring "answer" signal - no active call');
            break;
          }
          
          if (_currentCall!.id != data['callId']) {
            Logger.warning('⚠️ Ignoring "answer" signal - call ID mismatch (current: ${_currentCall!.id}, received: ${data['callId']})');
            break;
          }
          
          // CRITICAL: Only accept answer if we're in RINGING state
          // If we already canceled/ended the call, ignore the answer
          if (_currentCall!.state != CallState.ringing) {
            Logger.warning('⚠️ Ignoring "answer" signal - call not in ringing state (current state: ${_currentCall!.state})');
            Logger.info('🛡️ Race condition prevented: callee answered but caller already canceled');
            break;
          }
          
          if (_peerConnection == null) {
            Logger.error('❌ Cannot process answer: peer connection is null!');
            break;
          }
          
          Logger.info('✅ Answer signal valid, establishing WebRTC connection...');
          
          try {
            await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(data['sdp'] as String, 'answer'),
            );
            _hasRemoteDescription = true;

            Logger.debug('📞 Remote description set, updating call state to connecting');
            
            // CRITICAL: Apply any buffered ICE candidates that arrived before answer
            // ICE candidates can arrive via P2P before the answer signal due to network ordering
            await _drainPendingIceCandidates();

            // Stop ringtone when call is answered
            await _stopRingtone();

            // Keep state as CONNECTING until WebRTC connection is established
            _currentCall = _currentCall!.copyWith(
              state: CallState.connecting,
              remoteSDP: data['sdp'] as String,
            );
            _notifyCallState();

            // DO NOT start call timer here - it will start when WebRTC connection is established
            // in the onConnectionState callback
            
            Logger.info('✅ Answer processed successfully, waiting for WebRTC connection...');
            
            // CRITICAL FIX: Check connection state immediately after setRemoteDescription
            // Sometimes the WebRTC connection establishes so quickly that the onConnectionState
            // callback fires before we're ready, causing the UI to get stuck in "Connecting..."
            // This immediate check + delayed fallback ensures we always catch the connected state
            await Future.delayed(const Duration(milliseconds: 100));
            await _checkAndUpdateConnectionState();
            
            // Fallback: Check again after 2 seconds if still connecting
            // This handles edge cases where the callback never fires
            Future.delayed(const Duration(seconds: 2), () async {
              if (_currentCall?.state == CallState.connecting && !_isCleaningUp) {
                Logger.warning('⚠️ Still connecting after 2s, forcing connection state check...');
                await _checkAndUpdateConnectionState();
              }
            });
          } catch (e) {
            Logger.error('❌ Failed to set remote description: $e');
          }
          break;

        case 'ice':
          // ICE candidate
          Logger.debug('📞 Processing ICE candidate: current call ID=${_currentCall?.id}, incoming call ID=${data['callId']}, peerConnection exists=${_peerConnection != null}');
          
          if (_currentCall?.id == data['callId']) {
            // GUARD: Ignore ICE candidates if call is already ended
            // This prevents buffering candidates for a call that will never connect
            if (_currentCall!.state.isEnded) {
              Logger.debug('📞 Ignoring ICE candidate - call already ended (state: ${_currentCall!.state})');
              break;
            }
            
            try {
              final candidate = RTCIceCandidate(
                data['candidate'] as String,
                data['sdpMid'] as String,
                data['sdpMLineIndex'] as int,
              );
              
              // CRITICAL: ICE candidates can only be added AFTER remote description is set
              // Buffer them if peer connection doesn't exist OR remote description not set yet
              if (_peerConnection == null || !_hasRemoteDescription) {
                Logger.info('📦 Buffering ICE candidate (remote description not ready yet)');
                _pendingIceCandidates.add(candidate);
              } else {
                await _peerConnection!.addCandidate(candidate);
                Logger.debug('📞 ICE candidate added: ${(data['candidate'] as String).substring(0, 50)}...');
              }
            } catch (e) {
              Logger.error('❌ Failed to add ICE candidate: $e');
            }
          } else {
            Logger.info('📞 ICE candidate ignored: Call ID mismatch');
          }
          break;

        case 'reject':
          // Call rejected
          Logger.info('📞 Received "reject" signal from remote (callId: ${data['callId']}, current: ${_currentCall?.id})');
          
          if (_currentCall?.id == data['callId']) {
            Logger.info('📞 Remote rejected call, cleaning up...');
            
            _currentCall = _currentCall!.copyWith(state: CallState.rejected);
            _notifyCallState();
            await _saveCallToHistory(); // Save when remote rejects call
            
            await NotificationUtils.playCallEndTone();
            await _cleanup();
            
            // Clear call state after delay to allow UI to show "rejected" state
            // GUARD: Check call ID to prevent race condition
            final callIdToRemove = data['callId'] as String;
            Future.delayed(const Duration(seconds: 2), () {
              if (_currentCall?.id == callIdToRemove && _currentCall?.state == CallState.rejected) {
                Logger.debug('🧹 Clearing rejected call $callIdToRemove from state');
                _currentCall = null;
                _notifyCallState();
              }
            });
          } else {
            Logger.warning('⚠️ Received "reject" signal for different call ID (current: ${_currentCall?.id}, received: ${data['callId']})');
          }
          break;

        case 'end':
          // Call ended by remote
          Logger.info('📞 Received "end" signal from remote (callId: ${data['callId']}, current: ${_currentCall?.id})');
          
          if (_currentCall?.id == data['callId']) {
            Logger.info('📞 Remote ended call, cleaning up...');
            
            _currentCall = _currentCall!.copyWith(
              state: CallState.ended,
              duration: _callStartTime != null
                  ? DateTime.now().difference(_callStartTime!)
                  : null,
            );
            _notifyCallState();
            await _saveCallToHistory(); // Save when remote ends call
            
            await NotificationUtils.playCallEndTone();
            await _cleanup();
            
            // Clear call state after delay to allow UI to show "ended" state
            // GUARD: Check call ID to prevent race condition
            final callIdToRemove = data['callId'] as String;
            Future.delayed(const Duration(seconds: 2), () {
              if (_currentCall?.id == callIdToRemove && _currentCall?.state == CallState.ended) {
                Logger.debug('🧹 Clearing ended call $callIdToRemove from state');
                _currentCall = null;
                _notifyCallState();
              }
            });
          } else {
            Logger.warning('⚠️ Received "end" signal for different call ID (current: ${_currentCall?.id}, received: ${data['callId']})');
          }
          break;
        
        case 'busy':
          // Remote peer is busy (already in another call)
          Logger.info('📞 Received "busy" signal from remote (callId: ${data['callId']}, current: ${_currentCall?.id})');
          
          if (_currentCall?.id == data['callId']) {
            Logger.info('📞 Remote peer is busy, ending call...');
            
            _currentCall = _currentCall!.copyWith(state: CallState.failed);
            _notifyCallState();
            await _saveCallToHistory(); // Save when call fails (busy)
            
            await NotificationUtils.playCallEndTone();
            await _cleanup();
            
            // Clear call state after delay
            final callIdToRemove = data['callId'] as String;
            Future.delayed(const Duration(seconds: 2), () {
              if (_currentCall?.id == callIdToRemove && _currentCall?.state == CallState.failed) {
                Logger.debug('🧹 Clearing busy/failed call $callIdToRemove from state');
                _currentCall = null;
                _notifyCallState();
              }
            });
          } else {
            Logger.warning('⚠️ Received "busy" signal for different call ID (current: ${_currentCall?.id}, received: ${data['callId']})');
          }
          break;
      }
    } catch (e) {
      Logger.error('❌ Failed to handle signal: $e');
    }
  }

  // Private methods

  Future<void> _createPeerConnection() async {
    // Clean up any existing peer connection first
    if (_peerConnection != null) {
      Logger.warning('⚠️  Closing existing peer connection before creating new one');
      await _peerConnection!.close();
      _peerConnection = null;
    }
    
    Logger.debug('📞 Creating peer connection with ICE servers: $_iceServers');
    _peerConnection = await createPeerConnection(_iceServers);
    _hadActivePeerConnection = true; // Track that WebRTC has taken over audio session
    _hasRemoteDescription = false; // Reset flag for new peer connection
    Logger.debug('📞 Peer connection created successfully');

    // Handle ICE candidates
    int candidateCount = 0;
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      candidateCount++;
      Logger.debug('📞 [$candidateCount] ICE Candidate: ${candidate.candidate}');
      
      // Queue ICE candidate for sequential sending (prevents concurrent stream congestion)
      if (_currentCall != null) {
        final nodeMultiaddr = _currentCall!.connectedNodeMultiaddr ?? getActiveNode?.call();
        if (nodeMultiaddr != null) {
          final nodePeerID = _extractPeerID(nodeMultiaddr);
          
          // Add to queue
          _iceCandidateQueue.add(_QueuedIceCandidate(
            candidate: candidate,
            contactId: _currentCall!.contactId,
            nodePeerID: nodePeerID,
            callId: _currentCall!.id,
            sequenceNumber: candidateCount,
          ));
          
          Logger.debug('📦 [$candidateCount] ICE candidate queued (queue size: ${_iceCandidateQueue.length})');
          
          // Start queue worker if not already running
          _startICECandidateQueueWorker();
        } else {
          Logger.warning('⚠️  Cannot queue ICE candidate: no node available');
        }
      } else {
        Logger.warning('⚠️  Cannot queue ICE candidate: no active call');
      }
    };

    // Handle remote stream
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      Logger.debug('📞 Received remote track (streams: ${event.streams.length})');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream);
        Logger.info('✅ Remote audio stream connected');
      } else {
        Logger.error('❌ Received track event but no streams available! User will not hear audio.');
      }
    };

    // Handle connection state
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) async {
      Logger.debug('📞 Connection state changed: $state');
      
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        Logger.info('✅ WebRTC connection established!');
        
        // Stop call timeout timer (connection successful)
        _stopCallTimeoutTimer();
        
        // Only start timer if not already started (prevents duplicate timer)
        if (_callStartTime == null) {
          _startCallTimer();
          Logger.info('⏱️ Call timer started');
        }
        
        _currentCall = _currentCall?.copyWith(state: CallState.connected);
        _notifyCallState();
        await _saveCallToHistory(); // Save when call connects successfully
        
        // Enable speaker when connection is established
        await _enableSpeaker();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        Logger.error('❌ WebRTC connection ${state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ? "failed" : "closed"}');
        
        // Only cleanup if not already cleaning up (prevents double cleanup)
        if (!_isCleaningUp) {
          final isClosed = state == RTCPeerConnectionState.RTCPeerConnectionStateClosed;
          
          _currentCall = _currentCall?.copyWith(
            state: isClosed ? CallState.ended : CallState.failed,
          );
          _notifyCallState();
          await _saveCallToHistory(); // Save when WebRTC connection fails or closes
          
          // Play end tone if connection closed normally (remote hung up)
          if (isClosed) {
            await NotificationUtils.playCallEndTone();
          }
          
          await _cleanup();
          
          // Clear call state after delay
          // GUARD: Check call ID to prevent race condition
          final callIdToRemove = _currentCall?.id;
          Future.delayed(const Duration(seconds: 2), () {
            if (callIdToRemove != null && 
                _currentCall?.id == callIdToRemove && 
                (_currentCall?.state == CallState.failed || _currentCall?.state == CallState.ended)) {
              Logger.debug('🧹 Clearing failed/ended call $callIdToRemove from state (WebRTC fallback)');
              _currentCall = null;
              _notifyCallState();
            }
          });
        }
      }
    };
    
    // ICE connection state handler
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      Logger.debug('📞 ICE connection state: $state');
      
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        Logger.error('❌ ICE connection failed!');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateCompleted ||
          state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        Logger.info('✅ ICE connection established: $state');
        _stopICEGatheringPolls(); // Stop polling once ICE is connected
      }
    };
    
    // ICE gathering state handler
    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      Logger.debug('📞 🔍 ICE gathering state: $state');
      
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        Logger.info('✅ ICE gathering complete (total candidates: $candidateCount)');
      } else if (state == RTCIceGatheringState.RTCIceGatheringStateGathering) {
        Logger.info('🔄 ICE gathering started...');
      }
    };
  }

  Future<void> _addLocalStream() async {
    _localStream = await navigator.mediaDevices.getUserMedia(_mediaConstraints);
    
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    Logger.debug('📞 Local audio stream added');
  }

  /// Apply buffered ICE candidates that arrived before peer connection was ready
  Future<void> _drainPendingIceCandidates() async {
    if (_pendingIceCandidates.isEmpty) {
      return;
    }
    
    Logger.info('📦 Applying ${_pendingIceCandidates.length} buffered ICE candidate(s)');
    
    for (final candidate in _pendingIceCandidates) {
      try {
        await _peerConnection!.addCandidate(candidate);
        Logger.debug('✅ Buffered ICE candidate applied: ${candidate.candidate?.substring(0, 50)}...');
      } catch (e) {
        Logger.error('❌ Failed to apply buffered ICE candidate: $e');
      }
    }
    
    _pendingIceCandidates.clear();
    Logger.info('✅ All buffered ICE candidates applied');
  }

  Future<void> _sendCallSignal({
    required String contactId,
    required String nodePeerID,
    required String signalType,
    required Map<String, dynamic> data,
  }) async {
    try {
      Logger.debug('📞 Sending $signalType signal to $contactId via node $nodePeerID');

      final callId = data['callId'] as String? ?? '';
      if (callId.isEmpty) {
        throw ArgumentError('callId is required in data');
      }

      // Create signable data for call signal (sender:target:callID:signalType:timestamp)
      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final signableData = '${_identity.peerID}:$contactId:$callId:$signalType:$timestamp';
      
      Logger.debug('📝 Signing call signal: $signableData');
      
      // Sign the call signal
      final signResult = await _identity.sign(utf8.encode(signableData));
      if (signResult.isFailure) {
        Logger.warning('⚠️ Failed to sign call signal: ${signResult.errorOrNull?.userMessage}');
        throw Exception('Signature failed: ${signResult.errorOrNull?.message}');
      }
      
      final signature = signResult.valueOrNull!;
      final signatureBase64 = base64Encode(signature);
      Logger.debug('✅ Call signal signed (${signature.length} bytes, timestamp: $timestamp)');

      // Use P2P Bridge to send call signal via Oasis Node with signature
      await _p2pRepository.sendCallSignal(
        nodePeerID: nodePeerID,
        targetPeerID: contactId,
        signalType: signalType,
        callID: callId,
        data: data,
        signature: signatureBase64,
        signatureTimestamp: timestamp,
      );

      Logger.success('Call signal $signalType sent successfully');
    } catch (e) {
      Logger.error('❌ Failed to send call signal: $e');
      rethrow;
    }
  }

  /// Extract PeerID from multiaddr string
  String _extractPeerID(String multiaddr) {
    final parts = multiaddr.split('/p2p/');
    if (parts.length < 2) {
      throw FormatException('Invalid multiaddr format: missing /p2p/ component');
    }
    return parts.last;
  }

  void _startCallTimer() {
    _callStartTime = DateTime.now();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentCall != null && _callStartTime != null) {
        final duration = DateTime.now().difference(_callStartTime!);
        _currentCall = _currentCall!.copyWith(duration: duration);
        _notifyCallState();
      }
    });
  }

  /// Start rapid polling for ICE candidates during WebRTC negotiation
  /// Polls every 500ms for up to 30 seconds to gather all ICE candidates
  void _startICEGatheringPolls() {
    // Cancel any existing polling timer
    _iceGatheringTimer?.cancel();
    _iceGatheringPollCount = 0;
    
    if (triggerMessagePoll == null) {
      Logger.warning('⚠️  Cannot start ICE gathering polls: triggerMessagePoll callback not available');
      return;
    }
    
    Logger.debug('📞 🔄 Starting rapid ICE gathering polls (every 500ms for 30s)');
    
    // Poll every 500ms for up to 30 seconds (60 attempts)
    _iceGatheringTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      _iceGatheringPollCount++;
      
      // Stop if call ended or connected
      if (_currentCall == null || 
          _currentCall!.state == CallState.connected || 
          _currentCall!.state.isEnded) {
        Logger.debug('📞 🛑 Stopping ICE polls: call state=${_currentCall?.state}');
        timer.cancel();
        _iceGatheringTimer = null;
        return;
      }
      
      // Stop after 60 attempts (30 seconds)
      if (_iceGatheringPollCount >= 60) {
        Logger.debug('📞 🛑 Stopping ICE polls: reached max attempts (30s)');
        timer.cancel();
        _iceGatheringTimer = null;
        return;
      }
      
      // Trigger poll
      Logger.debug('📞 🔄 ICE poll #$_iceGatheringPollCount');
      try {
        await triggerMessagePoll!();
      } catch (e) {
        Logger.error('❌ ICE polling error: $e');
      }
    });
  }
  
  void _stopICEGatheringPolls() {
    if (_iceGatheringTimer != null) {
      Logger.debug('📞 🛑 Manually stopping ICE gathering polls');
      _iceGatheringTimer?.cancel();
      _iceGatheringTimer = null;
      _iceGatheringPollCount = 0;
    }
  }

  /// Start ICE candidate queue worker
  /// Processes queued ICE candidates sequentially to prevent concurrent stream congestion
  void _startICECandidateQueueWorker() {
    if (_iceCandidateQueueWorker != null && _iceCandidateQueueWorker!.isActive) {
      return; // Already running
    }
    
    Logger.debug('🔄 Starting ICE candidate queue worker');
    
    // Process queue every 100ms (allows ~10 candidates per second)
    _iceCandidateQueueWorker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _processICECandidateQueue();
    });
  }
  
  /// Stop ICE candidate queue worker
  void _stopICECandidateQueueWorker() {
    if (_iceCandidateQueueWorker != null) {
      Logger.debug('🛑 Stopping ICE candidate queue worker');
      _iceCandidateQueueWorker?.cancel();
      _iceCandidateQueueWorker = null;
    }
  }
  
  /// Process ICE candidate queue
  /// Sends one candidate at a time to prevent concurrent stream congestion
  Future<void> _processICECandidateQueue() async {
    // Guard: prevent concurrent processing
    if (_isProcessingIceQueue) {
      return;
    }
    
    // Guard: stop if queue is empty
    if (_iceCandidateQueue.isEmpty) {
      return;
    }
    
    // Guard: stop if call ended
    if (_currentCall == null || _currentCall!.state.isEnded) {
      Logger.debug('📦 Clearing ICE queue: call ended (${_iceCandidateQueue.length} candidates discarded)');
      _iceCandidateQueue.clear();
      _stopICECandidateQueueWorker();
      return;
    }
    
    _isProcessingIceQueue = true;
    
    try {
      // Dequeue one candidate
      final queuedCandidate = _iceCandidateQueue.removeAt(0);
      final seqNum = queuedCandidate.sequenceNumber;
      
      Logger.debug('📤 Processing ICE candidate #$seqNum from queue (${_iceCandidateQueue.length} remaining)');
      
      // Send the candidate
      try {
        await _sendCallSignal(
          contactId: queuedCandidate.contactId,
          nodePeerID: queuedCandidate.nodePeerID,
          signalType: 'ice',
          data: {
            'callId': queuedCandidate.callId,
            'candidate': queuedCandidate.candidate.candidate,
            'sdpMid': queuedCandidate.candidate.sdpMid,
            'sdpMLineIndex': queuedCandidate.candidate.sdpMLineIndex,
          },
        );
        Logger.success('✅ [$seqNum] ICE candidate sent successfully');
      } catch (e) {
        Logger.error('❌ Failed to send ICE candidate #$seqNum: $e');
        // Don't retry - continue with next candidate
      }
      
    } finally {
      _isProcessingIceQueue = false;
    }
    
    // Stop worker when queue is empty
    if (_iceCandidateQueue.isEmpty) {
      Logger.debug('✅ ICE candidate queue empty, stopping worker');
      _stopICECandidateQueueWorker();
    }
  }

  /// Start call timeout timer
  /// Auto-ends call after 120 seconds if stuck in ringing or connecting state
  void _startCallTimeoutTimer() {
    // Cancel any existing timeout timer
    _callTimeoutTimer?.cancel();
    
    Logger.debug('⏰ Starting call timeout timer (120 seconds)');
    
    _callTimeoutTimer = Timer(const Duration(seconds: 120), () async {
      if (_currentCall == null) return;
      
      final state = _currentCall!.state;
      
      // Only timeout if still in non-final state
      if (state == CallState.ringing || 
          state == CallState.connecting || 
          state == CallState.initiating) {
        Logger.warning('⏰ Call timeout! State: $state - Auto-ending call after 120 seconds');
        
        _currentCall = _currentCall!.copyWith(
          state: CallState.missed,
          duration: _callStartTime != null
              ? DateTime.now().difference(_callStartTime!)
              : null,
        );
        _notifyCallState();
        
        await _cleanup();
        
        // Clear after delay
        final callIdToRemove = _currentCall?.id;
        Future.delayed(const Duration(seconds: 2), () {
          if (callIdToRemove != null && _currentCall?.id == callIdToRemove) {
            Logger.debug('🧹 Clearing timed out call $callIdToRemove from state');
            _currentCall = null;
            _notifyCallState();
          }
        });
      }
    });
  }
  
  /// Stop call timeout timer
  void _stopCallTimeoutTimer() {
    if (_callTimeoutTimer != null) {
      Logger.debug('⏰ Stopping call timeout timer');
      _callTimeoutTimer?.cancel();
      _callTimeoutTimer = null;
    }
  }

  void _notifyCallState() {
    _callStateController.add(_currentCall);
  }

  /// Save call to persistent storage
  /// Should only be called for terminal or significant states:
  /// - connected (call started successfully)
  /// - ended (normal termination)
  /// - rejected (call declined)
  /// - failed (connection error)
  Future<void> _saveCallToHistory() async {
    if (_currentCall == null) return;
    
    // Only save calls in terminal or connected states
    final shouldSave = _currentCall!.state == CallState.connected ||
                       _currentCall!.state == CallState.ended ||
                       _currentCall!.state == CallState.rejected ||
                       _currentCall!.state == CallState.failed;
    
    if (!shouldSave) return;
    
    try {
      final result = await _storage.saveCall(_currentCall!);
      if (result.isSuccess) {
        Logger.debug('💾 Call saved to history: ${_currentCall!.id} (${_currentCall!.state})');
      } else {
        Logger.error('❌ Failed to save call to history: ${result.error}');
      }
    } catch (e) {
      Logger.error('❌ Exception saving call to history: $e');
    }
  }

  /// Check current WebRTC connection state and update call state if already connected
  /// This is a fallback for race conditions where onConnectionState callback might be missed
  Future<void> _checkAndUpdateConnectionState() async {
    if (_peerConnection == null || _currentCall == null) {
      Logger.debug('📞 _checkAndUpdateConnectionState: skipping (peerConnection or _currentCall is null)');
      return;
    }

    try {
      final connectionState = await _peerConnection!.connectionState;
      Logger.debug('📞 Current WebRTC connection state: $connectionState, Call state: ${_currentCall!.state}');

      if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (_currentCall!.state == CallState.connecting) {
          Logger.info('✅ WebRTC already connected! Updating call state from connecting to connected');
          
          _currentCall = _currentCall!.copyWith(state: CallState.connected);
          _notifyCallState();
          await _saveCallToHistory(); // Save when call connects successfully
          
          // Start call timer if not already started
          if (_callTimer == null) {
            _startCallTimer();
          }
        }
      }
    } catch (e) {
      Logger.error('❌ Error checking connection state: $e');
    }
  }

  /// Start playing ringtone (for outgoing ringing or incoming call)
  /// 
  /// [isIncoming] - true for incoming calls (uses incomingtone.mp3), false for outgoing (uses ringtone.mp3)
  Future<void> _startRingtone({required bool isIncoming}) async {
    if (_isRingtonePlaying) {
      return; // Already playing
    }
    
    try {
      // Ensure any previous player is fully disposed before creating new one
      // This prevents iOS audio session conflicts with voice messages
      if (_ringtonePlayer != null) {
        try {
          await _ringtonePlayer!.dispose();
          Logger.debug('🔕 Disposed previous ringtone player before starting new one');
        } catch (e) {
          Logger.warning('⚠️ Failed to dispose previous ringtone player: $e');
        }
        _ringtonePlayer = null;
      }
      
      // Create fresh AudioPlayer for ringtone
      _ringtonePlayer = AudioPlayer();
      
      // Use loop mode for continuous ringing
      await _ringtonePlayer!.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer!.setVolume(0.8);
      
      // Select appropriate ringtone based on call direction
      final soundFile = isIncoming 
          ? 'sounds/incomingtone.mp3'  // Incoming call sound
          : 'sounds/ringtone.mp3';      // Outgoing call sound
      
      // Try to play custom ringtone from assets
      // If file doesn't exist, it will fail gracefully without breaking the call
      try {
        await _ringtonePlayer!.play(AssetSource(soundFile));
        _isRingtonePlaying = true;
        Logger.info('🔔 ${isIncoming ? "Incoming" : "Outgoing"} ringtone started ($soundFile)');
      } catch (e) {
        Logger.warning('⚠️ Ringtone asset not found ($soundFile), call continues silently');
        // Continue without ringtone - not critical for call functionality
      }
    } catch (e) {
      Logger.error('❌ Failed to start ringtone: $e');
      // Continue without ringtone - not critical
    }
  }

  /// Stop playing ringtone
  Future<void> _stopRingtone() async {
    if (!_isRingtonePlaying || _ringtonePlayer == null) {
      return;
    }
    
    try {
      // CRITICAL: Stop AND dispose the player immediately
      // This prevents iOS from reactivating the looped AudioPlayer 
      // when voice messages change the audio session
      await _ringtonePlayer!.stop();
      
      // Reset release mode to prevent iOS from auto-resuming in loop
      await _ringtonePlayer!.setReleaseMode(ReleaseMode.release);
      
      // Dispose player completely to release iOS audio session
      await _ringtonePlayer!.dispose();
      _ringtonePlayer = null;
      
      _isRingtonePlaying = false;
      Logger.info('🔕 Ringtone stopped and disposed');
      
      // Small delay to ensure iOS audio session is fully released
      // This prevents conflicts with voice message playback
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      Logger.error('❌ Failed to stop ringtone: $e');
      // Force reset state even on error
      _isRingtonePlaying = false;
      _ringtonePlayer = null;
    }
  }

  Future<void> _cleanup() async {
    // Guard: prevent multiple cleanup calls
    if (_isCleaningUp) {
      Logger.debug('⚠️ Cleanup already in progress, skipping...');
      return;
    }
    
    _isCleaningUp = true;
    Logger.debug('🧹 Starting cleanup...');
    
    // Stop call timeout timer
    _stopCallTimeoutTimer();
    
    // Stop ringtone
    await _stopRingtone();
    
    // Stop call timer
    _callTimer?.cancel();
    _callTimer = null;
    _callStartTime = null;
    
    // Stop ICE gathering polls
    _stopICEGatheringPolls();
    
    // Stop ICE candidate queue worker and clear queue
    _stopICECandidateQueueWorker();
    _iceCandidateQueue.clear();
    
    // Clear pending ICE candidates
    _pendingIceCandidates.clear();

    // Stop local stream
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;

    // Stop remote stream
    _remoteStream?.getTracks().forEach((track) => track.stop());
    _remoteStream?.dispose();
    _remoteStream = null;
    _remoteStreamController.add(null);

    // Close peer connection
    final hadPeerConnection = _peerConnection != null;
    await _peerConnection?.close();
    _peerConnection = null;
    _hasRemoteDescription = false;

    // Disable fast polling - ensure we return to normal interval even if endCall wasn't called
    disableFastPolling?.call();
    
    // Only reset audio session if WebRTC was actually used (PeerConnection was created)
    // This prevents crashes when call ends before being accepted (no WebRTC audio session takeover)
    if (_hadActivePeerConnection && hadPeerConnection) {
      Logger.debug('🔊 Resetting audio session (WebRTC was active)...');
      
      // Small delay to allow WebRTC to fully release audio resources
      await Future.delayed(const Duration(milliseconds: 200));

      // Reset audio session - completely deactivate WebRTC audio and restore normal playback
      try {
        // Turn off speaker
        await Helper.setSpeakerphoneOn(false);
        
        // CRITICAL: Explicitly reset iOS AVAudioSession to playback mode
        // WebRTC sets it to playAndRecord+voiceChat which blocks AudioPlayer
        // Using playback with mixWithOthers for maximum compatibility
        await Helper.setAppleAudioConfiguration(
          AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playback,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.mixWithOthers,
            },
            appleAudioMode: AppleAudioMode.default_,
          ),
        );
        
        // Small delay to ensure iOS processes the configuration change
        await Future.delayed(const Duration(milliseconds: 100));
        
        Logger.info('🔊 Audio session reset: category=playback, mixWithOthers=true, mode=default');
      } catch (e) {
        Logger.error('⚠️ Failed to reset audio session: $e');
        // Fallback: try simple mode reset
        try {
          await Helper.setAppleAudioIOMode(
            AppleAudioIOMode.none,
            preferSpeakerOutput: false,
          );
          Logger.info('🔊 Audio session reset via fallback method');
        } catch (fallbackError) {
          Logger.error('⚠️ Fallback audio reset also failed: $fallbackError');
        }
      }
    } else {
      Logger.debug('ℹ️  Skipping audio session reset (WebRTC was never initialized)');
    }
    
    // Dispose ringtone player if it still exists (already disposed in _stopRingtone normally)
    if (_ringtonePlayer != null) {
      try {
        await _ringtonePlayer!.dispose();
        _ringtonePlayer = null;
        Logger.debug('🔕 Ringtone player disposed in cleanup');
      } catch (e) {
        Logger.error('⚠️ Failed to dispose ringtone player: $e');
      }
    }
    
    // Reset flag
    _hadActivePeerConnection = false;

    Logger.debug('📞 Call cleanup completed');
    _isCleaningUp = false;
  }

  /// Dispose service
  Future<void> dispose() async {
    await _callSignalSubscription?.cancel();
    _stopICECandidateQueueWorker(); // Ensure queue worker is stopped
    await _cleanup(); // cleanup already disposes ringtone player
    await _callStateController.close();
    await _remoteStreamController.close();
  }
}

/// Internal helper class to queue ICE candidates with metadata
class _QueuedIceCandidate {
  final RTCIceCandidate candidate;
  final String contactId;
  final String nodePeerID;
  final String callId;
  final int sequenceNumber;
  
  _QueuedIceCandidate({
    required this.candidate,
    required this.contactId,
    required this.nodePeerID,
    required this.callId,
    required this.sequenceNumber,
  });
}
