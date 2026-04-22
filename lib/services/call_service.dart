import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class CallService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RealtimeChannel? _signalingChannel;
  String? _activePeerId;
  void Function(IncomingCallOffer offer)? _incomingOfferHandler;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _hasRemoteDescription = false;

  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _callStateController = StreamController<CallState>.broadcast();

  Stream<MediaStream> get remoteStream => _remoteStreamController.stream;
  Stream<CallState> get callState => _callStateController.stream;

  String get _myId => supabase.auth.currentUser!.id;

  // ICE servers - Cloudflare STUN works in China, TURN is mandatory for reliability
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.cloudflare.com:3478'},
      {'urls': 'stun:stun1.l.google.com:19302'}, // fallback for India side
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ── Start a call (caller side) ──
  Future<MediaStream> startCall({required bool videoCall}) async {
    _callStateController.add(CallState.calling);
    _localStream = await _getUserMedia(videoCall: videoCall);
    _activePeerId = await _findPartnerId();
    await _createPeerConnection();
    await _listenForSignals();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await _sendSignal('offer', {
      'sdp': offer.sdp,
      'type': offer.type,
      'videoCall': videoCall,
      'callerName': await _myDisplayName(),
    });

    return _localStream!;
  }

  // ── Answer an incoming call ──
  Future<MediaStream> answerCall({
    required String callerId,
    required Map<String, dynamic> offerData,
    required bool videoCall,
  }) async {
    _activePeerId = callerId;
    _callStateController.add(CallState.connecting);
    _localStream = await _getUserMedia(videoCall: videoCall);
    await _createPeerConnection();
    await _listenForSignals();

    final offer = RTCSessionDescription(
      offerData['sdp'] as String,
      offerData['type'] as String,
    );
    await _peerConnection!.setRemoteDescription(offer);
    _hasRemoteDescription = true;

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await _sendSignal('answer', {
      'sdp': answer.sdp,
      'type': answer.type,
    });

    await _flushPendingCandidates();

    return _localStream!;
  }

  Future<void> rejectCall({required String callerId}) async {
    _activePeerId = callerId;
    await _sendSignal('hangup', {});
    _activePeerId = null;
  }

  // ── Hang up ──
  Future<void> hangUp() async {
    await _sendSignal('hangup', {});
    _cleanup();
    _callStateController.add(CallState.idle);
  }

  Future<MediaStream> _getUserMedia({required bool videoCall}) async {
    return await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': videoCall
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    // Add local tracks
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Handle remote stream
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream!);
        _callStateController.add(CallState.connected);
      }
    };

    // Send ICE candidates via Supabase
    _peerConnection!.onIceCandidate = (candidate) async {
      if (candidate.candidate != null) {
        await _sendSignal('candidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _callStateController.add(CallState.idle);
      }
    };
  }

  void listenForIncomingCalls(void Function(IncomingCallOffer offer) onIncomingCall) {
    _incomingOfferHandler = onIncomingCall;
    _callStateController.add(CallState.idle);
    _listenForSignals();
  }

  Future<void> _listenForSignals() async {
    if (_signalingChannel != null) {
      return;
    }

    _signalingChannel = supabase
        .channel('signals-$_myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_user',
            value: _myId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final type = data['type'] as String;
            final signalData = Map<String, dynamic>.from(
              (data['data'] as Map?) ?? const {},
            );
            final fromUser = data['from_user'] as String?;
            final signalId = data['id'] as String?;

            switch (type) {
              case 'offer':
                if (fromUser == null) {
                  break;
                }
                _activePeerId = fromUser;
                _callStateController.add(CallState.ringing);
                _incomingOfferHandler?.call(
                  IncomingCallOffer(
                    signalId: signalId ?? '',
                    callerId: fromUser,
                    callerName: signalData['callerName'] as String? ?? 'Partner',
                    videoCall: signalData['videoCall'] as bool? ?? false,
                    offerData: signalData,
                  ),
                );
                break;

              case 'answer':
                final answer = RTCSessionDescription(
                  signalData['sdp'] as String,
                  signalData['type'] as String,
                );
                await _peerConnection?.setRemoteDescription(answer);
                _hasRemoteDescription = true;
                await _flushPendingCandidates();
                _callStateController.add(CallState.connected);
                break;

              case 'candidate':
                final candidate = RTCIceCandidate(
                  signalData['candidate'] as String,
                  signalData['sdpMid'] as String?,
                  signalData['sdpMLineIndex'] as int?,
                );
                if (_peerConnection == null || !_hasRemoteDescription) {
                  _pendingCandidates.add(candidate);
                } else {
                  await _peerConnection?.addCandidate(candidate);
                }
                break;

              case 'hangup':
                _cleanup();
                _callStateController.add(CallState.idle);
                break;
            }
          },
        )
        .subscribe();
  }

  Future<void> _sendSignal(String type, Map<String, dynamic> data) async {
    final peerId = _activePeerId ?? await _findPartnerId();

    await supabase.from('signals').insert({
      'from_user': _myId,
      'to_user': peerId,
      'type': type,
      'data': data,
    });
  }

  Future<String> _findPartnerId() async {
    final pair = await supabase.from('app_pair').select('user_a, user_b').single();
    final a = pair['user_a'] as String;
    final b = pair['user_b'] as String;
    return a == _myId ? b : a;
  }

  Future<String> _myDisplayName() async {
    final profile = await supabase
        .from('profiles')
        .select('name')
        .eq('id', _myId)
        .maybeSingle();
    return profile?['name'] as String? ?? 'Partner';
  }

  Future<void> _flushPendingCandidates() async {
    if (_peerConnection == null || !_hasRemoteDescription) {
      return;
    }

    for (final candidate in List<RTCIceCandidate>.from(_pendingCandidates)) {
      await _peerConnection?.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  void _cleanup() {
    _pendingCandidates.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _hasRemoteDescription = false;
    _activePeerId = null;
    _signalingChannel?.unsubscribe();
    _signalingChannel = null;
  }

  // ── Public controls for mute/camera ──
  void toggleMute(bool muted) {
    _localStream?.getAudioTracks().forEach((t) {
      t.enabled = !muted;
    });
  }

  void toggleCamera(bool cameraOff) {
    _localStream?.getVideoTracks().forEach((t) {
      t.enabled = !cameraOff;
    });
  }

  void dispose() {
    _cleanup();
    _remoteStreamController.close();
    _callStateController.close();
  }
}

class IncomingCallOffer {
  final String signalId;
  final String callerId;
  final String callerName;
  final bool videoCall;
  final Map<String, dynamic> offerData;

  const IncomingCallOffer({
    required this.signalId,
    required this.callerId,
    required this.callerName,
    required this.videoCall,
    required this.offerData,
  });
}

enum CallState { idle, calling, ringing, connecting, connected }
