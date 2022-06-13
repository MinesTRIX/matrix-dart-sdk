/*
 *   Famedly Matrix SDK
 *   Copyright (C) 2021 Famedly GmbH
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as
 *   published by the Free Software Foundation, either version 3 of the
 *   License, or (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:core';

import 'package:webrtc_interface/webrtc_interface.dart';

import '../../matrix.dart';

/// https://github.com/matrix-org/matrix-doc/pull/2746
/// version 1
const String voipProtoVersion = '1';

/// The default life time for call events, in millisecond.
const lifetimeMs = 10 * 1000;

/// The length of time a call can be ringing for.
const callTimeoutSec = 60;

/// Wrapped MediaStream, used to adapt Widget to display
class WrappedMediaStream {
  MediaStream? stream;
  final String userId;
  final Room room;

  /// Current stream type, usermedia or screen-sharing
  String purpose;
  bool audioMuted;
  bool videoMuted;
  final Client client;
  VideoRenderer renderer;
  final bool isWeb;
  final bool isGroupCall;

  /// for debug
  String get title => '$displayName:$purpose:a[$audioMuted]:v[$videoMuted]';
  bool stopped = false;

  final StreamController<WrappedMediaStream> onMuteStateChanged =
      StreamController.broadcast();

  void Function(MediaStream stream)? onNewStream;

  WrappedMediaStream(
      {this.stream,
      required this.renderer,
      required this.room,
      required this.userId,
      required this.purpose,
      required this.client,
      required this.audioMuted,
      required this.videoMuted,
      required this.isWeb,
      required this.isGroupCall});

  /// Initialize the video renderer
  Future<void> initialize() async {
    await renderer.initialize();
    renderer.srcObject = stream;
    renderer.onResize = () {
      Logs().i(
          'onResize [${stream!.id.substring(0, 8)}] ${renderer.videoWidth} x ${renderer.videoHeight}');
    };
  }

  Future<void> dispose() async {
    renderer.srcObject = null;
    if (isLocal() && !isGroupCall && stream != null) {
      if (isWeb) {
        stream!.getTracks().forEach((element) {
          element.stop();
        });
      }
      await stream?.dispose();
      stream = null;
    }
  }

  Uri? get avatarUrl => getUser().avatarUrl;

  String get avatarName =>
      getUser().calcDisplayname(mxidLocalPartFallback: false);

  String? get displayName => getUser().displayName;

  User getUser() {
    return room.unsafeGetUserFromMemoryOrFallback(userId);
  }

  bool isLocal() {
    return userId == client.userID;
  }

  bool isAudioMuted() {
    return (stream != null && stream!.getAudioTracks().isEmpty) || audioMuted;
  }

  bool isVideoMuted() {
    return (stream != null && stream!.getVideoTracks().isEmpty) || videoMuted;
  }

  void setNewStream(MediaStream newStream) {
    stream = newStream;
    renderer.srcObject = stream;
    if (onNewStream != null) {
      onNewStream?.call(stream!);
    }
  }

  void setAudioMuted(bool muted) {
    audioMuted = muted;
    onMuteStateChanged.add(this);
  }

  void setVideoMuted(bool muted) {
    videoMuted = muted;
    onMuteStateChanged.add(this);
  }
}

// Call state
enum CallState {
  /// The call is inilalized but not yet started
  kFledgling,

  /// The first time an invite is sent, the local has createdOffer
  kInviteSent,

  /// getUserMedia or getDisplayMedia has been called,
  /// but MediaStream has not yet been returned
  kWaitLocalMedia,

  /// The local has createdOffer
  kCreateOffer,

  /// Received a remote offer message and created a local Answer
  kCreateAnswer,

  /// Answer sdp is set, but ice is not connected
  kConnecting,

  /// WebRTC media stream is connected
  kConnected,

  /// The call was received, but no processing has been done yet.
  kRinging,

  /// End of call
  kEnded,
}

class CallErrorCode {
  /// The user chose to end the call
  static String UserHangup = 'user_hangup';

  /// An error code when the local client failed to create an offer.
  static String LocalOfferFailed = 'local_offer_failed';

  /// An error code when there is no local mic/camera to use. This may be because
  /// the hardware isn't plugged in, or the user has explicitly denied access.
  static String NoUserMedia = 'no_user_media';

  /// Error code used when a call event failed to send
  /// because unknown devices were present in the room
  static String UnknownDevices = 'unknown_devices';

  /// Error code used when we fail to send the invite
  /// for some reason other than there being unknown devices
  static String SendInvite = 'send_invite';

  /// An answer could not be created

  static String CreateAnswer = 'create_answer';

  /// Error code used when we fail to send the answer
  /// for some reason other than there being unknown devices

  static String SendAnswer = 'send_answer';

  /// The session description from the other side could not be set
  static String SetRemoteDescription = 'set_remote_description';

  /// The session description from this side could not be set
  static String SetLocalDescription = 'set_local_description';

  /// A different device answered the call
  static String AnsweredElsewhere = 'answered_elsewhere';

  /// No media connection could be established to the other party
  static String IceFailed = 'ice_failed';

  /// The invite timed out whilst waiting for an answer
  static String InviteTimeout = 'invite_timeout';

  /// The call was replaced by another call
  static String Replaced = 'replaced';

  /// Signalling for the call could not be sent (other than the initial invite)
  static String SignallingFailed = 'signalling_timeout';

  /// The remote party is busy
  static String UserBusy = 'user_busy';

  /// We transferred the call off to somewhere else
  static String Transfered = 'transferred';
}

class CallError extends Error {
  final String code;
  final String msg;
  final dynamic err;
  CallError(this.code, this.msg, this.err);

  @override
  String toString() {
    return '[$code] $msg, err: ${err.toString()}';
  }
}

enum CallEvent {
  /// The call was hangup by the local|remote user.
  kHangup,

  /// The call state has changed
  kState,

  /// The call got some error.
  kError,

  /// Call transfer
  kReplaced,

  /// The value of isLocalOnHold() has changed
  kLocalHoldUnhold,

  /// The value of isRemoteOnHold() has changed
  kRemoteHoldUnhold,

  /// Feeds have changed
  kFeedsChanged,

  /// For sip calls. support in the future.
  kAssertedIdentityChanged,
}

enum CallType { kVoice, kVideo }

enum CallDirection { kIncoming, kOutgoing }

enum CallParty { kLocal, kRemote }

/// Initialization parameters of the call session.
class CallOptions {
  late String callId;
  String? groupCallId;
  late CallType type;
  late CallDirection dir;
  late String localPartyId;
  late VoIP voip;
  late Room room;
  late List<Map<String, dynamic>> iceServers;
}

/// A call session object
class CallSession {
  CallSession(this.opts);
  CallOptions opts;
  CallType get type => opts.type;
  Room get room => opts.room;
  VoIP get voip => opts.voip;
  String? get groupCallId => opts.groupCallId;
  String get callId => opts.callId;
  String get localPartyId => opts.localPartyId;
  String? get displayName => room.displayname;
  CallDirection get direction => opts.dir;
  CallState state = CallState.kFledgling;
  bool get isOutgoing => direction == CallDirection.kOutgoing;
  bool get isRinging => state == CallState.kRinging;
  RTCPeerConnection? pc;
  List<RTCIceCandidate> remoteCandidates = <RTCIceCandidate>[];
  List<RTCIceCandidate> localCandidates = <RTCIceCandidate>[];
  late AssertedIdentity remoteAssertedIdentity;
  bool get callHasEnded => state == CallState.kEnded;
  bool iceGatheringFinished = false;
  bool inviteOrAnswerSent = false;
  bool localHold = false;
  bool remoteOnHold = false;
  bool _answeredByUs = false;
  bool speakerOn = false;
  bool makingOffer = false;
  bool ignoreOffer = false;
  String facingMode = 'user';
  bool get answeredByUs => _answeredByUs;
  Client get client => opts.room.client;
  String? remotePartyId;
  String? opponentDeviceId;
  String? opponentSessionId;
  String? invitee;
  User? remoteUser;
  late CallParty hangupParty;
  String? hangupReason;
  late CallError lastError;
  CallSession? successor;
  bool waitForLocalAVStream = false;
  int toDeviceSeq = 0;

  final StreamController<CallSession> onCallStreamsChanged =
      StreamController.broadcast();

  final StreamController<CallSession> onCallReplaced =
      StreamController.broadcast();

  final StreamController<CallSession> onCallHangup =
      StreamController.broadcast();

  final StreamController<CallState> onCallStateChanged =
      StreamController.broadcast();

  final StreamController<CallEvent> onCallEventChanged =
      StreamController.broadcast();

  final StreamController<WrappedMediaStream> onStreamAdd =
      StreamController.broadcast();

  final StreamController<WrappedMediaStream> onStreamRemoved =
      StreamController.broadcast();

  SDPStreamMetadata? remoteSDPStreamMetadata;
  List<RTCRtpSender> usermediaSenders = [];
  List<RTCRtpSender> screensharingSenders = [];
  List<WrappedMediaStream> streams = <WrappedMediaStream>[];
  List<WrappedMediaStream> get getLocalStreams =>
      streams.where((element) => element.isLocal()).toList();
  List<WrappedMediaStream> get getRemoteStreams =>
      streams.where((element) => !element.isLocal()).toList();

  WrappedMediaStream? get localUserMediaStream {
    final stream = getLocalStreams.where(
        (element) => element.purpose == SDPStreamMetadataPurpose.Usermedia);
    if (stream.isNotEmpty) {
      return stream.first;
    }
    return null;
  }

  WrappedMediaStream? get localScreenSharingStream {
    final stream = getLocalStreams.where(
        (element) => element.purpose == SDPStreamMetadataPurpose.Screenshare);
    if (stream.isNotEmpty) {
      return stream.first;
    }
    return null;
  }

  WrappedMediaStream? get remoteUserMediaStream {
    final stream = getRemoteStreams.where(
        (element) => element.purpose == SDPStreamMetadataPurpose.Usermedia);
    if (stream.isNotEmpty) {
      return stream.first;
    }
    return null;
  }

  WrappedMediaStream? get remoteScreenSharingStream {
    final stream = getRemoteStreams.where(
        (element) => element.purpose == SDPStreamMetadataPurpose.Screenshare);
    if (stream.isNotEmpty) {
      return stream.first;
    }
    return null;
  }

  Timer? inviteTimer;
  Timer? ringingTimer;

  Future<void> initOutboundCall(CallType type) async {
    await _preparePeerConnection();
    setCallState(CallState.kCreateOffer);
    final stream = await _getUserMedia(type);
    if (stream != null) {
      addLocalStream(stream, SDPStreamMetadataPurpose.Usermedia);
    }
  }

  Future<void> initWithInvite(CallType type, RTCSessionDescription offer,
      SDPStreamMetadata? metadata, int lifetime) async {
    await _preparePeerConnection();

    final stream = await _getUserMedia(type);
    if (stream != null) {
      addLocalStream(stream, SDPStreamMetadataPurpose.Usermedia);
    }

    if (metadata != null) {
      _updateRemoteSDPStreamMetadata(metadata);
    }

    await pc!.setRemoteDescription(offer);

    setCallState(CallState.kRinging);

    ringingTimer = Timer(Duration(milliseconds: 30000 - lifetime), () {
      if (state == CallState.kRinging) {
        Logs().v('[VOIP] Call invite has expired. Hanging up.');
        hangupParty = CallParty.kRemote; // effectively
        fireCallEvent(CallEvent.kHangup);
        hangup(CallErrorCode.InviteTimeout);
      }
      ringingTimer?.cancel();
      ringingTimer = null;
    });
  }

  void answerWithStreams(List<WrappedMediaStream> callFeeds) {
    if (inviteOrAnswerSent) return;
    Logs().d('nswering call $callId');
    gotCallFeedsForAnswer(callFeeds);
  }

  void replacedBy(CallSession newCall) {
    if (state == CallState.kWaitLocalMedia) {
      Logs().v('Telling new call to wait for local media');
      newCall.waitForLocalAVStream = true;
    } else if (state == CallState.kCreateOffer ||
        state == CallState.kInviteSent) {
      Logs().v('Handing local stream to new call');
      newCall.gotCallFeedsForAnswer(getLocalStreams);
    }
    successor = newCall;
    onCallReplaced.add(newCall);
    hangup(CallErrorCode.Replaced, true);
  }

  Future<void> sendAnswer(RTCSessionDescription answer) async {
    final callCapabilities = CallCapabilities()
      ..dtmf = false
      ..transferee = false;

    final metadata = SDPStreamMetadata({
      localUserMediaStream!.stream!.id: SDPStreamPurpose(
          purpose: SDPStreamMetadataPurpose.Usermedia,
          audio_muted: localUserMediaStream!.stream!.getAudioTracks().isEmpty,
          video_muted: localUserMediaStream!.stream!.getVideoTracks().isEmpty)
    });

    final res = await sendAnswerCall(room, callId, answer.sdp!, localPartyId,
        type: answer.type!, capabilities: callCapabilities, metadata: metadata);
    Logs().v('[VOIP] answer res => $res');
  }

  Future<void> gotCallFeedsForAnswer(List<WrappedMediaStream> callFeeds) async {
    if (state == CallState.kEnded) return;

    waitForLocalAVStream = false;

    callFeeds.forEach((element) {
      // Safari can't send a MediaStream to multiple sources, so clone it
      addLocalStream(element.stream!.clone(), element.purpose);
    });

    answer();
  }

  Future<void> placeCallWithStreams(List<WrappedMediaStream> callFeeds,
      [bool requestScreenshareFeed = false]) async {
    opts.dir = CallDirection.kOutgoing;

    voip.calls[callId] = this;

    // create the peer connection now so it can be gathering candidates while we get user
    // media (assuming a candidate pool size is configured)
    await _preparePeerConnection();
    gotCallFeedsForInvite(callFeeds, requestScreenshareFeed);
  }

  void gotCallFeedsForInvite(List<WrappedMediaStream> callFeeds,
      [bool requestScreenshareFeed = false]) {
    if (successor != null) {
      successor!.gotCallFeedsForAnswer(callFeeds);
      return;
    }
    if (state == CallState.kEnded) {
      cleanUp();
      return;
    }

    callFeeds.forEach((element) {
      addLocalStream(element.stream!.clone(), element.purpose);
    });

    if (requestScreenshareFeed) {
      pc!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init:
              RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
    }

    setCallState(CallState.kCreateOffer);

    Logs().d('gotUserMediaForInvite');
    // Now we wait for the negotiationneeded event
  }

  void initWithHangup() {
    setCallState(CallState.kEnded);
  }

  void onAnswerReceived(
      RTCSessionDescription answer, SDPStreamMetadata? metadata) async {
    if (metadata != null) {
      _updateRemoteSDPStreamMetadata(metadata);
    }

    if (direction == CallDirection.kOutgoing) {
      setCallState(CallState.kConnecting);
      await pc!.setRemoteDescription(answer);
      remoteCandidates.forEach((candidate) => pc!.addCandidate(candidate));
    }

    /// Send select_answer event.
    await sendSelectCallAnswer(
        opts.room, callId, lifetimeMs, localPartyId, remotePartyId!);
  }

  void onNegotiateReceived(
      SDPStreamMetadata? metadata, RTCSessionDescription description) async {
    final polite = direction == CallDirection.kIncoming;

    // Here we follow the perfect negotiation logic from
    // https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Perfect_negotiation
    final offerCollision = ((description.type == 'offer') &&
        (makingOffer ||
            pc!.signalingState != RTCSignalingState.RTCSignalingStateStable));

    ignoreOffer = !polite && offerCollision;
    if (ignoreOffer) {
      Logs().i('Ignoring colliding negotiate event because we\'re impolite');
      return;
    }

    final prevLocalOnHold = await isLocalOnHold();

    if (metadata != null) {
      _updateRemoteSDPStreamMetadata(metadata);
    }

    try {
      await pc!.setRemoteDescription(description);
      if (description.type == 'offer') {
        final answer = await pc!.createAnswer({});
        await sendCallNegotiate(
            room, callId, lifetimeMs, localPartyId, answer.sdp!,
            type: answer.type!);
        await pc!.setLocalDescription(answer);
      }
    } catch (e) {
      _getLocalOfferFailed(e);
      Logs().e('[VOIP] onNegotiateReceived => ${e.toString()}');
      return;
    }

    final newLocalOnHold = await isLocalOnHold();
    if (prevLocalOnHold != newLocalOnHold) {
      localHold = newLocalOnHold;
      fireCallEvent(CallEvent.kLocalHoldUnhold);
    }
  }

  void _updateRemoteSDPStreamMetadata(SDPStreamMetadata metadata) {
    remoteSDPStreamMetadata = metadata;
    remoteSDPStreamMetadata!.sdpStreamMetadatas
        .forEach((streamId, sdpStreamMetadata) {
      Logs().i(
          'Stream purpose update: \nid = "$streamId", \npurpose = "${sdpStreamMetadata.purpose}",  \naudio_muted = ${sdpStreamMetadata.audio_muted}, \nvideo_muted = ${sdpStreamMetadata.video_muted}');
    });
    getRemoteStreams.forEach((wpstream) {
      final streamId = wpstream.stream!.id;
      final purpose = metadata.sdpStreamMetadatas[streamId];
      if (purpose != null) {
        wpstream
            .setAudioMuted(metadata.sdpStreamMetadatas[streamId]!.audio_muted);
        wpstream
            .setVideoMuted(metadata.sdpStreamMetadatas[streamId]!.video_muted);
        wpstream.purpose = metadata.sdpStreamMetadatas[streamId]!.purpose;
      } else {
        Logs().i('Not found purpose for remote stream $streamId, remove it?');
        wpstream.stopped = true;
        fireCallEvent(CallEvent.kFeedsChanged);
      }
    });
  }

  void onSDPStreamMetadataReceived(SDPStreamMetadata metadata) async {
    _updateRemoteSDPStreamMetadata(metadata);
    fireCallEvent(CallEvent.kFeedsChanged);
  }

  void onCandidatesReceived(List<dynamic> candidates) {
    candidates.forEach((json) async {
      final candidate = RTCIceCandidate(
        json['candidate'],
        json['sdpMid'] ?? '',
        json['sdpMLineIndex']?.round() ?? 0,
      );

      if (pc != null && inviteOrAnswerSent && remotePartyId != null) {
        try {
          await pc!.addCandidate(candidate);
        } catch (e) {
          Logs().e('[VOIP] onCandidatesReceived => ${e.toString()}');
        }
      } else {
        remoteCandidates.add(candidate);
      }
    });

    if (pc != null &&
        pc!.iceConnectionState ==
            RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      restartIce();
    }
  }

  void onAssertedIdentityReceived(AssertedIdentity identity) async {
    remoteAssertedIdentity = identity;
    fireCallEvent(CallEvent.kAssertedIdentityChanged);
  }

  bool get screensharingEnabled => localScreenSharingStream != null;

  Future<bool> setScreensharingEnabled(bool enabled) async {
    // Skip if there is nothing to do
    if (enabled && localScreenSharingStream != null) {
      Logs().w(
          'There is already a screensharing stream - there is nothing to do!');
      return true;
    } else if (!enabled && localScreenSharingStream == null) {
      Logs().w(
          'There already isn\'t a screensharing stream - there is nothing to do!');
      return false;
    }

    Logs().d('Set screensharing enabled? $enabled');

    if (enabled) {
      try {
        final stream = await _getDisplayMedia();
        if (stream == null) {
          return false;
        }
        stream.getVideoTracks().forEach((track) {
          track.onEnded = () {
            setScreensharingEnabled(false);
          };
        });
        addLocalStream(stream, SDPStreamMetadataPurpose.Screenshare);
        return true;
      } catch (err) {
        fireCallEvent(CallEvent.kError);
        lastError = CallError(CallErrorCode.NoUserMedia,
            'Failed to get screen-sharing stream: ', err);
        return false;
      }
    } else {
      for (final sender in screensharingSenders) {
        await pc!.removeTrack(sender);
      }
      for (final track in localScreenSharingStream!.stream!.getTracks()) {
        await track.stop();
      }
      localScreenSharingStream!.stopped = true;
      await _removeStream(localScreenSharingStream!.stream!);
      fireCallEvent(CallEvent.kFeedsChanged);
      return false;
    }
  }

  void addLocalStream(MediaStream stream, String purpose,
      {bool addToPeerConnection = true}) async {
    final existingStream =
        getLocalStreams.where((element) => element.purpose == purpose);
    if (existingStream.isNotEmpty) {
      existingStream.first.setNewStream(stream);
    } else {
      final newStream = WrappedMediaStream(
          renderer: voip.delegate.createRenderer(),
          userId: client.userID!,
          room: opts.room,
          stream: stream,
          purpose: purpose,
          client: client,
          audioMuted: stream.getAudioTracks().isEmpty,
          videoMuted: stream.getVideoTracks().isEmpty,
          isWeb: voip.delegate.isWeb,
          isGroupCall: groupCallId != null);
      await newStream.initialize();
      streams.add(newStream);
      onStreamAdd.add(newStream);
    }

    if (addToPeerConnection) {
      if (purpose == SDPStreamMetadataPurpose.Screenshare) {
        screensharingSenders.clear();
        stream.getTracks().forEach((track) async {
          screensharingSenders.add(await pc!.addTrack(track, stream));
        });
      } else if (purpose == SDPStreamMetadataPurpose.Usermedia) {
        usermediaSenders.clear();
        stream.getTracks().forEach((track) async {
          usermediaSenders.add(await pc!.addTrack(track, stream));
        });
      }
    }

    if (purpose == SDPStreamMetadataPurpose.Usermedia) {
      speakerOn = type == CallType.kVideo;
      if (!voip.delegate.isWeb && !voip.delegate.isBackgroud) {
        final audioTrack = stream.getAudioTracks()[0];
        audioTrack.enableSpeakerphone(speakerOn);
      }
    }

    fireCallEvent(CallEvent.kFeedsChanged);
  }

  void _addRemoteStream(MediaStream stream) async {
    //final userId = remoteUser.id;
    final metadata = remoteSDPStreamMetadata!.sdpStreamMetadatas[stream.id];
    if (metadata == null) {
      Logs().i(
          'Ignoring stream with id ${stream.id} because we didn\'t get any metadata about it');
      return;
    }

    final purpose = metadata.purpose;
    final audioMuted = metadata.audio_muted;
    final videoMuted = metadata.video_muted;

    // Try to find a feed with the same purpose as the new stream,
    // if we find it replace the old stream with the new one
    final existingStream =
        getRemoteStreams.where((element) => element.purpose == purpose);
    if (existingStream.isNotEmpty) {
      existingStream.first.setNewStream(stream);
    } else {
      final newStream = WrappedMediaStream(
          renderer: voip.delegate.createRenderer(),
          userId: remoteUser!.id,
          room: opts.room,
          stream: stream,
          purpose: purpose,
          client: client,
          audioMuted: audioMuted,
          videoMuted: videoMuted,
          isWeb: voip.delegate.isWeb,
          isGroupCall: groupCallId != null);
      await newStream.initialize();
      streams.add(newStream);
      onStreamAdd.add(newStream);
    }
    fireCallEvent(CallEvent.kFeedsChanged);
    Logs().i('Pushed remote stream (id="${stream.id}", purpose=$purpose)');
  }

  void deleteAllStreams() {
    streams.forEach((stream) async {
      if (stream.isLocal() || groupCallId == null) {
        await stream.dispose();
      }
    });
    streams.clear();
    fireCallEvent(CallEvent.kFeedsChanged);
  }

  void deleteFeedByStream(MediaStream stream) {
    final index =
        streams.indexWhere((element) => element.stream!.id == stream.id);
    if (index == -1) {
      Logs().w('Didn\'t find the feed with stream id ${stream.id} to delete');
      return;
    }
    final wstream = streams.elementAt(index);
    onStreamRemoved.add(wstream);
    deleteStream(wstream);
  }

  void deleteStream(WrappedMediaStream stream) {
    stream.dispose();
    streams.removeAt(streams.indexOf(stream));
    fireCallEvent(CallEvent.kFeedsChanged);
  }

  void removeLocalStream(WrappedMediaStream callFeed) {
    final senderArray = callFeed.purpose == SDPStreamMetadataPurpose.Usermedia
        ? usermediaSenders
        : screensharingSenders;

    senderArray.forEach((element) async {
      await pc!.removeTrack(element);
    });

    if (callFeed.purpose == SDPStreamMetadataPurpose.Screenshare) {
      stopMediaStream(callFeed.stream);
    }

    // Empty the array
    senderArray.removeRange(0, senderArray.length);
    onStreamRemoved.add(callFeed);
    deleteStream(callFeed);
  }

  void setCallState(CallState newState) {
    state = newState;
    onCallStateChanged.add(newState);
    fireCallEvent(CallEvent.kState);
  }

  void setLocalVideoMuted(bool muted) {
    localUserMediaStream?.setVideoMuted(muted);
    _updateMuteStatus();
  }

  bool get isLocalVideoMuted => localUserMediaStream?.isVideoMuted() ?? false;

  void setMicrophoneMuted(bool muted) {
    localUserMediaStream?.setAudioMuted(muted);
    _updateMuteStatus();
  }

  bool get isMicrophoneMuted => localUserMediaStream?.isAudioMuted() ?? false;

  void setRemoteOnHold(bool onHold) async {
    if (isRemoteOnHold == onHold) return;
    remoteOnHold = onHold;
    final transceivers = await pc!.getTransceivers();
    for (final transceiver in transceivers) {
      await transceiver.setDirection(onHold
          ? TransceiverDirection.SendOnly
          : TransceiverDirection.SendRecv);
    }
    _updateMuteStatus();
    fireCallEvent(CallEvent.kRemoteHoldUnhold);
  }

  bool get isRemoteOnHold => remoteOnHold;

  Future<bool> isLocalOnHold() async {
    if (state != CallState.kConnected) return false;
    var callOnHold = true;
    // We consider a call to be on hold only if *all* the tracks are on hold
    // (is this the right thing to do?)
    final transceivers = await pc!.getTransceivers();
    for (final transceiver in transceivers) {
      final currentDirection = await transceiver.getCurrentDirection();
      Logs()
          .i('transceiver.currentDirection = ${currentDirection?.toString()}');
      final trackOnHold = (currentDirection == TransceiverDirection.Inactive ||
          currentDirection == TransceiverDirection.RecvOnly);
      if (!trackOnHold) {
        callOnHold = false;
      }
    }
    return callOnHold;
  }

  void answer() async {
    if (inviteOrAnswerSent) {
      return;
    }
    // stop play ringtone
    voip.delegate.stopRingtone();

    if (direction == CallDirection.kIncoming) {
      setCallState(CallState.kCreateAnswer);

      final answer = await pc!.createAnswer({});
      remoteCandidates.forEach((candidate) => pc!.addCandidate(candidate));

      final callCapabilities = CallCapabilities()
        ..dtmf = false
        ..transferee = false;

      final metadata = SDPStreamMetadata({
        localUserMediaStream!.stream!.id: SDPStreamPurpose(
            purpose: SDPStreamMetadataPurpose.Usermedia,
            audio_muted: localUserMediaStream!.stream!.getAudioTracks().isEmpty,
            video_muted: localUserMediaStream!.stream!.getVideoTracks().isEmpty)
      });

      final res = await sendAnswerCall(room, callId, answer.sdp!, localPartyId,
          type: answer.type!,
          capabilities: callCapabilities,
          metadata: metadata);
      Logs().v('[VOIP] answer res => $res');
      await pc!.setLocalDescription(answer);
      setCallState(CallState.kConnecting);
      inviteOrAnswerSent = true;
      _answeredByUs = true;
    }
  }

  /// Reject a call
  /// This used to be done by calling hangup, but is a separate method and protocol
  /// event as of MSC2746.
  ///
  void reject() {
    if (state != CallState.kRinging) {
      Logs().e('[VOIP] Call must be in \'ringing\' state to reject!');
      return;
    }
    Logs().d('[VOIP] Rejecting call: $callId');
    terminate(CallParty.kLocal, CallErrorCode.UserHangup, true);
    sendCallReject(room, callId, lifetimeMs, localPartyId);
  }

  void hangup([String? reason, bool suppressEvent = true]) async {
    // stop play ringtone
    voip.delegate.stopRingtone();

    terminate(
        CallParty.kLocal, reason ?? CallErrorCode.UserHangup, !suppressEvent);

    try {
      final res =
          await sendHangupCall(room, callId, localPartyId, 'userHangup');
      Logs().v('[VOIP] hangup res => $res');
    } catch (e) {
      Logs().v('[VOIP] hangup error => ${e.toString()}');
    }
  }

  void sendDTMF(String tones) async {
    final senders = await pc!.getSenders();
    for (final sender in senders) {
      if (sender.track != null && sender.track!.kind == 'audio') {
        await sender.dtmfSender.insertDTMF(tones);
        return;
      }
    }
    Logs().e('Unable to find a track to send DTMF on');
  }

  void terminate(CallParty party, String reason, bool shouldEmit) async {
    if (state == CallState.kEnded) {
      return;
    }

    inviteTimer?.cancel();
    inviteTimer = null;

    ringingTimer?.cancel();
    ringingTimer = null;

    hangupParty = party;
    hangupReason = reason;

    setCallState(CallState.kEnded);
    voip.currentCID = null;
    voip.calls.remove(callId);
    cleanUp();

    onCallHangup.add(this);

    voip.delegate.handleCallEnded(this);
    if (shouldEmit) {
      fireCallEvent(CallEvent.kHangup);
    }
  }

  void onRejectReceived(String? reason) {
    Logs().v('[VOIP] Reject received for call ID ' + callId);
    // No need to check party_id for reject because if we'd received either
    // an answer or reject, we wouldn't be in state InviteSent
    final shouldTerminate = (state == CallState.kFledgling &&
            direction == CallDirection.kIncoming) ||
        CallState.kInviteSent == state ||
        CallState.kRinging == state;

    if (shouldTerminate) {
      terminate(CallParty.kRemote, reason ?? CallErrorCode.UserHangup, true);
    } else {
      Logs().e('Call is in state: ${state.toString()}: ignoring reject');
    }
  }

  Future<void> _gotLocalOffer(RTCSessionDescription offer) async {
    if (callHasEnded) {
      Logs().d(
          'Ignoring newly created offer on call ID ${opts.callId} because the call has ended');
      return;
    }

    try {
      await pc!.setLocalDescription(offer);
    } catch (err) {
      Logs().d('Error setting local description! ${err.toString()}');
      terminate(CallParty.kLocal, CallErrorCode.SetLocalDescription, true);
      return;
    }

    if (callHasEnded) return;

    final callCapabilities = CallCapabilities()
      ..dtmf = false
      ..transferee = false;
    final metadata = _getLocalSDPStreamMetadata();
    if (state == CallState.kCreateOffer) {
      await sendInviteToCall(
          room, callId, lifetimeMs, localPartyId, null, offer.sdp!,
          capabilities: callCapabilities, metadata: metadata);
      inviteOrAnswerSent = true;
      setCallState(CallState.kInviteSent);

      inviteTimer = Timer(Duration(seconds: callTimeoutSec), () {
        if (state == CallState.kInviteSent) {
          hangup(CallErrorCode.InviteTimeout, false);
        }
        inviteTimer?.cancel();
        inviteTimer = null;
      });
    } else {
      await sendCallNegotiate(
          room, callId, lifetimeMs, localPartyId, offer.sdp!,
          type: offer.type!,
          capabilities: callCapabilities,
          metadata: metadata);
    }
  }

  void onNegotiationNeeded() async {
    Logs().i('Negotiation is needed!');
    makingOffer = true;
    try {
      final offer = await pc!.createOffer({});
      await _gotLocalOffer(offer);
    } catch (e) {
      _getLocalOfferFailed(e);
      return;
    } finally {
      makingOffer = false;
    }
  }

  Future<void> _preparePeerConnection() async {
    try {
      pc = await _createPeerConnection();

      pc!.onRenegotiationNeeded = onNegotiationNeeded;

      pc!.onIceCandidate = (RTCIceCandidate candidate) async {
        //Logs().v('[VOIP] onIceCandidate => ${candidate.toMap().toString()}');
        localCandidates.add(candidate);
      };
      pc!.onIceGatheringState = (RTCIceGatheringState state) async {
        Logs().v('[VOIP] IceGatheringState => ${state.toString()}');
        if (state == RTCIceGatheringState.RTCIceGatheringStateGathering) {
          Timer(Duration(seconds: 3), () async {
            if (!iceGatheringFinished) {
              iceGatheringFinished = true;
              await _candidateReady();
            }
          });
        }
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
          if (!iceGatheringFinished) {
            iceGatheringFinished = true;
            await _candidateReady();
          }
        }
      };
      pc!.onIceConnectionState = (RTCIceConnectionState state) {
        Logs().v('[VOIP] RTCIceConnectionState => ${state.toString()}');
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          localCandidates.clear();
          remoteCandidates.clear();
          setCallState(CallState.kConnected);
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          hangup(CallErrorCode.IceFailed, false);
        }
      };
    } catch (e) {
      Logs().v('[VOIP] prepareMediaStream error => ${e.toString()}');
    }
  }

  void onAnsweredElsewhere() {
    Logs().d('Call ID $callId answered elsewhere');
    terminate(CallParty.kRemote, CallErrorCode.AnsweredElsewhere, true);
  }

  void cleanUp() async {
    streams.forEach((stream) {
      stream.dispose();
    });
    streams.clear();
    if (pc != null) {
      await pc!.close();
      await pc!.dispose();
    }
  }

  void _updateMuteStatus() async {
    final micShouldBeMuted = (localUserMediaStream != null &&
            localUserMediaStream!.isAudioMuted()) ||
        remoteOnHold;
    final vidShouldBeMuted = (localUserMediaStream != null &&
            localUserMediaStream!.isVideoMuted()) ||
        remoteOnHold;

    _setTracksEnabled(localUserMediaStream?.stream!.getAudioTracks() ?? [],
        !micShouldBeMuted);
    _setTracksEnabled(localUserMediaStream?.stream!.getVideoTracks() ?? [],
        !vidShouldBeMuted);

    await sendSDPStreamMetadataChanged(
        room, callId, localPartyId, _getLocalSDPStreamMetadata());
  }

  void _setTracksEnabled(List<MediaStreamTrack> tracks, bool enabled) {
    tracks.forEach((track) async {
      track.enabled = enabled;
    });
  }

  SDPStreamMetadata _getLocalSDPStreamMetadata() {
    final sdpStreamMetadatas = <String, SDPStreamPurpose>{};
    for (final wpstream in getLocalStreams) {
      sdpStreamMetadatas[wpstream.stream!.id] = SDPStreamPurpose(
          purpose: wpstream.purpose,
          audio_muted: wpstream.audioMuted,
          video_muted: wpstream.videoMuted);
    }
    final metadata = SDPStreamMetadata(sdpStreamMetadatas);
    Logs().v('Got local SDPStreamMetadata ${metadata.toJson().toString()}');
    return metadata;
  }

  void restartIce() async {
    Logs().v('[VOIP] iceRestart.');
    // Needs restart ice on session.pc and renegotiation.
    iceGatheringFinished = false;
    final desc =
        await pc!.createOffer(_getOfferAnswerConstraints(iceRestart: true));
    await pc!.setLocalDescription(desc);
    localCandidates.clear();
  }

  Future<MediaStream?> _getUserMedia(CallType type) async {
    final mediaConstraints = {
      'audio': true,
      'video': type == CallType.kVideo
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };
    try {
      return await voip.delegate.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      _getUserMediaFailed(e);
    }
    return null;
  }

  Future<MediaStream?> _getDisplayMedia() async {
    final mediaConstraints = {
      'audio': false,
      'video': true,
    };
    try {
      return await voip.delegate.mediaDevices.getDisplayMedia(mediaConstraints);
    } catch (e) {
      _getUserMediaFailed(e);
    }
    return null;
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': opts.iceServers,
      'sdpSemantics': 'unified-plan'
    };
    final pc = await voip.delegate.createPeerConnection(configuration);
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        final stream = event.streams[0];
        _addRemoteStream(stream);
        stream.getVideoTracks().forEach((track) {
          track.onEnded = () {
            _removeStream(stream);
          };
        });
      }
    };
    return pc;
  }

  void createDataChannel(String label, RTCDataChannelInit dataChannelDict) {
    pc?.createDataChannel(label, dataChannelDict);
  }

  void tryRemoveStopedStreams() {
    final removedStreams = <String, WrappedMediaStream>{};
    streams.forEach((stream) {
      if (stream.stopped) {
        removedStreams[stream.stream!.id] = stream;
      }
    });
    streams
        .removeWhere((stream) => removedStreams.containsKey(stream.stream!.id));
    removedStreams.forEach((id, element) {
      _removeStream(element.stream!);
    });
  }

  Future<void> _removeStream(MediaStream stream) async {
    Logs().v('Removing feed with stream id ${stream.id}');

    final it = streams.where((element) => element.stream!.id == stream.id);
    if (it.isEmpty) {
      Logs().v('Didn\'t find the feed with stream id ${stream.id} to delete');
      return;
    }
    final wpstream = it.first;
    streams.removeWhere((element) => element.stream!.id == stream.id);
    onStreamRemoved.add(wpstream);
    fireCallEvent(CallEvent.kFeedsChanged);
    await wpstream.dispose();
  }

  Map<String, dynamic> _getOfferAnswerConstraints({bool iceRestart = false}) {
    return {
      'mandatory': {if (iceRestart) 'IceRestart': true},
      'optional': [],
    };
  }

  Future<void> _candidateReady() async {
    /*
    Currently, trickle-ice is not supported, so it will take a
    long time to wait to collect all the canidates, set the
    timeout for collection canidates to speed up the connection.
    */
    try {
      final candidates = <Map<String, dynamic>>[];
      localCandidates.forEach((element) {
        candidates.add(element.toMap());
      });
      final res =
          await sendCallCandidates(opts.room, callId, localPartyId, candidates);
      Logs().v('[VOIP] sendCallCandidates res => $res');
    } catch (e) {
      Logs().v('[VOIP] sendCallCandidates e => ${e.toString()}');
    }
  }

  void fireCallEvent(CallEvent event) {
    onCallEventChanged.add(event);
    Logs().i('CallEvent: ${event.toString()}');
    switch (event) {
      case CallEvent.kFeedsChanged:
        onCallStreamsChanged.add(this);
        break;
      case CallEvent.kState:
        Logs().i('CallState: ${state.toString()}');
        break;
      case CallEvent.kError:
        break;
      case CallEvent.kHangup:
        break;
      case CallEvent.kReplaced:
        break;
      case CallEvent.kLocalHoldUnhold:
        break;
      case CallEvent.kRemoteHoldUnhold:
        break;
      case CallEvent.kAssertedIdentityChanged:
        break;
    }
  }

  void _getLocalOfferFailed(dynamic err) {
    Logs().e('Failed to get local offer ${err.toString()}');
    fireCallEvent(CallEvent.kError);
    lastError = CallError(
        CallErrorCode.LocalOfferFailed, 'Failed to get local offer!', err);
    terminate(CallParty.kLocal, CallErrorCode.LocalOfferFailed, false);
  }

  void _getUserMediaFailed(dynamic err) {
    if (state != CallState.kConnected) {
      Logs().w('Failed to get user media - ending call ${err.toString()}');
      fireCallEvent(CallEvent.kError);
      lastError = CallError(
          CallErrorCode.NoUserMedia,
          'Couldn\'t start capturing media! Is your microphone set up and does this app have permission?',
          err);
      terminate(CallParty.kLocal, CallErrorCode.NoUserMedia, false);
    }
  }

  void onSelectAnswerReceived(String? selectedPartyId) {
    if (direction != CallDirection.kIncoming) {
      Logs().w('Got select_answer for an outbound call: ignoring');
      return;
    }
    if (selectedPartyId == null) {
      Logs().w(
          'Got nonsensical select_answer with null/undefined selected_party_id: ignoring');
      return;
    }

    if (selectedPartyId != localPartyId) {
      Logs().w(
          'Got select_answer for party ID $selectedPartyId: we are party ID $localPartyId.');
      // The other party has picked somebody else's answer
      terminate(CallParty.kRemote, CallErrorCode.AnsweredElsewhere, true);
    }
  }

  /// This is sent by the caller when they wish to establish a call.
  /// [callId] is a unique identifier for the call.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [lifetime] is the time in milliseconds that the invite is valid for. Once the invite age exceeds this value,
  /// clients should discard it. They should also no longer show the call as awaiting an answer in the UI.
  /// [type] The type of session description. Must be 'offer'.
  /// [sdp] The SDP text of the session description.
  /// [invitee] The user ID of the person who is being invited. Invites without an invitee field are defined to be
  /// intended for any member of the room other than the sender of the event.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  Future<String?> sendInviteToCall(Room room, String callId, int lifetime,
      String party_id, String? invitee, String sdp,
      {String type = 'offer',
      String version = voipProtoVersion,
      String? txid,
      CallCapabilities? capabilities,
      SDPStreamMetadata? metadata}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';

    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      'lifetime': lifetime,
      'offer': {'sdp': sdp, 'type': type},
      if (invitee != null) 'invitee': invitee,
      if (capabilities != null) 'capabilities': capabilities.toJson(),
      if (metadata != null) sdpStreamMetadataKey: metadata.toJson(),
    };
    return await _sendContent(
      room,
      EventTypes.CallInvite,
      content,
      txid: txid,
    );
  }

  /// The calling party sends the party_id of the first selected answer.
  ///
  /// Usually after receiving the first answer sdp in the client.onCallAnswer event,
  /// save the `party_id`, and then send `CallSelectAnswer` to others peers that the call has been picked up.
  ///
  /// [callId] is a unique identifier for the call.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  /// [selected_party_id] The party ID for the selected answer.
  Future<String?> sendSelectCallAnswer(Room room, String callId, int lifetime,
      String party_id, String selected_party_id,
      {String version = voipProtoVersion, String? txid}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';

    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      'lifetime': lifetime,
      'selected_party_id': selected_party_id,
    };

    return await _sendContent(
      room,
      EventTypes.CallSelectAnswer,
      content,
      txid: txid,
    );
  }

  /// Reject a call
  /// [callId] is a unique identifier for the call.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  Future<String?> sendCallReject(
      Room room, String callId, int lifetime, String party_id,
      {String version = voipProtoVersion, String? txid}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';

    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      'lifetime': lifetime,
    };

    return await _sendContent(
      room,
      EventTypes.CallReject,
      content,
      txid: txid,
    );
  }

  /// When local audio/video tracks are added/deleted or hold/unhold,
  /// need to createOffer and renegotiation.
  /// [callId] is a unique identifier for the call.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  Future<String?> sendCallNegotiate(
      Room room, String callId, int lifetime, String party_id, String sdp,
      {String type = 'offer',
      String version = voipProtoVersion,
      String? txid,
      CallCapabilities? capabilities,
      SDPStreamMetadata? metadata}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';
    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      'lifetime': lifetime,
      'description': {'sdp': sdp, 'type': type},
      if (capabilities != null) 'capabilities': capabilities.toJson(),
      if (metadata != null) sdpStreamMetadataKey: metadata.toJson(),
    };
    return await _sendContent(
      room,
      EventTypes.CallNegotiate,
      content,
      txid: txid,
    );
  }

  /// This is sent by callers after sending an invite and by the callee after answering.
  /// Its purpose is to give the other party additional ICE candidates to try using to communicate.
  ///
  /// [callId] The ID of the call this event relates to.
  ///
  /// [version] The version of the VoIP specification this messages adheres to. This specification is version 1.
  ///
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  ///
  /// [candidates] Array of objects describing the candidates. Example:
  ///
  /// ```
  /// [
  ///       {
  ///           "candidate": "candidate:863018703 1 udp 2122260223 10.9.64.156 43670 typ host generation 0",
  ///           "sdpMLineIndex": 0,
  ///           "sdpMid": "audio"
  ///       }
  ///   ],
  /// ```
  Future<String?> sendCallCandidates(
    Room room,
    String callId,
    String party_id,
    List<Map<String, dynamic>> candidates, {
    String version = voipProtoVersion,
    String? txid,
  }) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';
    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      'candidates': candidates,
    };
    return await _sendContent(
      room,
      EventTypes.CallCandidates,
      content,
      txid: txid,
    );
  }

  /// This event is sent by the callee when they wish to answer the call.
  /// [callId] is a unique identifier for the call.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [type] The type of session description. Must be 'answer'.
  /// [sdp] The SDP text of the session description.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  Future<String?> sendAnswerCall(
      Room room, String callId, String sdp, String party_id,
      {String type = 'answer',
      String version = voipProtoVersion,
      String? txid,
      CallCapabilities? capabilities,
      SDPStreamMetadata? metadata}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';
    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      'answer': {'sdp': sdp, 'type': type},
      if (capabilities != null) 'capabilities': capabilities.toJson(),
      if (metadata != null) sdpStreamMetadataKey: metadata.toJson(),
    };
    return await _sendContent(
      room,
      EventTypes.CallAnswer,
      content,
      txid: txid,
    );
  }

  /// This event is sent by the callee when they wish to answer the call.
  /// [callId] The ID of the call this event relates to.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  Future<String?> sendHangupCall(
      Room room, String callId, String party_id, String? hangupCause,
      {String version = voipProtoVersion, String? txid}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';

    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      if (hangupCause != null) 'reason': hangupCause,
    };
    return await _sendContent(
      room,
      EventTypes.CallHangup,
      content,
      txid: txid,
    );
  }

  /// Send SdpStreamMetadata Changed event.
  ///
  /// This MSC also adds a new call event m.call.sdp_stream_metadata_changed,
  /// which has the common VoIP fields as specified in
  /// MSC2746 (version, call_id, party_id) and a sdp_stream_metadata object which
  /// is the same thing as sdp_stream_metadata in m.call.negotiate, m.call.invite
  /// and m.call.answer. The client sends this event the when sdp_stream_metadata
  /// has changed but no negotiation is required
  ///  (e.g. the user mutes their camera/microphone).
  ///
  /// [callId] The ID of the call this event relates to.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  /// [metadata] The sdp_stream_metadata object.
  Future<String?> sendSDPStreamMetadataChanged(
      Room room, String callId, String party_id, SDPStreamMetadata metadata,
      {String version = voipProtoVersion, String? txid}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';
    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      sdpStreamMetadataKey: metadata.toJson(),
    };
    return await _sendContent(
      room,
      EventTypes.CallSDPStreamMetadataChangedPrefix,
      content,
      txid: txid,
    );
  }

  /// CallReplacesEvent for Transfered calls
  ///
  /// [callId] The ID of the call this event relates to.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  /// [callReplaces] transfer info
  Future<String?> sendCallReplaces(
      Room room, String callId, String party_id, CallReplaces callReplaces,
      {String version = voipProtoVersion, String? txid}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';
    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      ...callReplaces.toJson(),
    };
    return await _sendContent(
      room,
      EventTypes.CallReplaces,
      content,
      txid: txid,
    );
  }

  /// send AssertedIdentity event
  ///
  /// [callId] The ID of the call this event relates to.
  /// [version] is the version of the VoIP specification this message adheres to. This specification is version 1.
  /// [party_id] The party ID for call, Can be set to client.deviceId.
  /// [assertedIdentity] the asserted identity
  Future<String?> sendAssertedIdentity(Room room, String callId,
      String party_id, AssertedIdentity assertedIdentity,
      {String version = voipProtoVersion, String? txid}) async {
    txid ??= 'txid${DateTime.now().millisecondsSinceEpoch}';
    final content = {
      'call_id': callId,
      'party_id': party_id,
      if (groupCallId != null) 'conf_id': groupCallId,
      'version': version,
      'asserted_identity': assertedIdentity.toJson(),
    };
    return await _sendContent(
      room,
      EventTypes.CallAssertedIdentity,
      content,
      txid: txid,
    );
  }

  Future<String?> _sendContent(
    Room room,
    String type,
    Map<String, dynamic> content, {
    String? txid,
  }) async {
    txid ??= client.generateUniqueTransactionId();
    final mustEncrypt = room.encrypted && client.encryptionEnabled;
    if (opponentDeviceId != null) {
      final toDeviceSeq = this.toDeviceSeq++;

      if (mustEncrypt) {
        await client.sendToDeviceEncrypted(
            [
              client.userDeviceKeys[invitee ?? remoteUser!.id]!
                  .deviceKeys[opponentDeviceId]!
            ],
            type,
            {
              ...content,
              'device_id': client.deviceID!,
              'seq': toDeviceSeq,
              'dest_session_id': opponentSessionId,
              'sender_session_id': client.groupCallSessionId,
            });
      } else {
        final data = <String, Map<String, Map<String, dynamic>>>{};
        data[invitee ?? remoteUser!.id] = {
          opponentDeviceId!: {
            ...content,
            'device_id': client.deviceID!,
            'seq': toDeviceSeq,
            'dest_session_id': opponentSessionId,
            'sender_session_id': client.groupCallSessionId,
          }
        };
        await client.sendToDevice(type, txid, data);
      }
      return '';
    } else {
      final sendMessageContent = mustEncrypt
          ? await client.encryption!
              .encryptGroupMessagePayload(room.id, content, type: type)
          : content;
      return await client.sendMessage(
        room.id,
        sendMessageContent.containsKey('ciphertext')
            ? EventTypes.Encrypted
            : type,
        txid,
        sendMessageContent,
      );
    }
  }
}