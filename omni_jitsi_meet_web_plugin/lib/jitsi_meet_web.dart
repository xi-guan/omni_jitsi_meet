import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:omni_jitsi_meet_platform_interface/jitsi_meet_platform_interface.dart';
import 'package:js/js.dart';

import 'jitsi_meet_external_api.dart' as jitsi;
import 'room_name_constraint.dart';
import 'room_name_constraint_type.dart';

/// JitsiMeetPlugin Web version for Jitsi Meet plugin
class JitsiMeetPlugin extends JitsiMeetPlatform {
  /// config
  static const _default_server = "meet.jit.si";
  static const _view_id = 'jitsi-meet-view';
  static const _section_id = 'jitsi-meet-section';

  /// events
  // static const _conferenceWillJoin = "conferenceWillJoin"; // is not supported in web
  static const _videoConferenceJoined = "videoConferenceJoined";
  static const _videoConferenceLeft = "videoConferenceLeft";
  static const _participantsInfoRetrieved = "participantsInfoRetrieved";
  static const _participantJoined = "participantJoined";
  static const _participantLeft = "participantLeft";
  static const _chatUpdated = "chatUpdated";
  static const _incomingMessage = "incomingMessage";
  static const _audioMuteStatusChanged = "audioMuteStatusChanged";
  static const _videoMuteStatusChanged = "videoMuteStatusChanged";
  static const _screenSharingStatusChanged = "screenSharingStatusChanged";
  static const _feedbackSubmitted = "feedbackSubmitted";
  static const _readyToClose = "readyToClose";

  /// Regex to validate URL
  static RegExp _cleanDomain = RegExp(r"^https?://");

  /// `JitsiMeetPlugin` instance
  static final JitsiMeetPlugin _instance = JitsiMeetPlugin._();

  /// Registry web plugin
  static void registerWith(Registrar registrar) => JitsiMeetPlatform.instance = _instance;

  /// `JitsiMeetExternalAPI` holder
  jitsi.JitsiMeetAPI? api;

  /// Flag to indicate if external JS are already added used for extra scripts
  bool extraJSAdded = false;

  /// Regex to validate URL

  JitsiMeetPlugin._() {
    _setupScripts();
  }

  /// Joins a meeting based on the JitsiMeetingOptions passed in.
  /// A JitsiMeetingListener can be attached to this meeting
  /// that will automatically be removed when the meeting has ended
  @override
  Future<JitsiMeetingResponse> joinMeeting(
    JitsiMeetingOptions options, {
    JitsiMeetingListener? listener,
    Map<RoomNameConstraintType, RoomNameConstraint>? roomNameConstraints,
  }) async {
    // encode `options` Map to Json to avoid error in interoperability conversions
    final webOptions = jsonEncode(options.webOptions);
    String serverURL = options.serverURL ?? _default_server;
    serverURL = serverURL.replaceAll(_cleanDomain, "");
    api = jitsi.JitsiMeetAPI(serverURL, webOptions);

    // setup listeners
    if (listener != null) {
      listener.onOpened?.call();

      // - `onConferenceWillJoin` is not supported or nof found event in web

      // - on conference joined
      api?.on(_videoConferenceJoined, allowInterop((dynamic _message) {
        listener.onConferenceJoined?.call(_message.toString());
      }));

      // - on conference left
      api?.on(_videoConferenceLeft, allowInterop((message) {
        final data = {'url': !kReleaseMode ? message.roomName : '?', 'error': message?.error};
        listener.onConferenceTerminated?.call(data["url"].toString(), data["error"]);
        listener.onClosed?.call();
      }));

      // - on participants info retrieved
      api?.on(_participantsInfoRetrieved, allowInterop((message) {
        final data = {
          'participantsInfo': !kReleaseMode ? message.participantsInfo : {},
          'requestId': !kReleaseMode ? message.requestId : '?'
        };
        listener.onParticipantsInfoRetrieved?.call(
          data["participantsInfo"] ?? {},
          data["requestId"]?.toString() ?? '?',
        );
      }));

      // - on participant joined
      api?.on(_participantJoined, allowInterop((message) {
        final data = {
          'email': !kReleaseMode ? message.email : '?',
          'name': !kReleaseMode ? message.displayName : '?',
          'role': !kReleaseMode ? message.role : '?',
          'participantId': !kReleaseMode ? message.id : '?',
        };
        listener.onParticipantJoined?.call(
          data["email"]?.toString() ?? "?",
          data["name"]?.toString() ?? "?",
          data["role"]?.toString() ?? "?",
          data["participantId"]?.toString() ?? "?",
        );
      }));

      // - on participant left
      api?.on(_participantLeft, allowInterop((message) {
        final data = {"participantId": !kReleaseMode ? message.id : '?'};
        listener.onParticipantLeft?.call(data["participantId"]?.toString() ?? "?");
      }));

      // - on chat updated
      api?.on(_chatUpdated, allowInterop((message) {
        final data = {
          'isOpen': !kReleaseMode ? message.isOpen : false,
          'unreadCount': !kReleaseMode ? message.unreadCount : 0,
        };
        listener.onChatToggled?.call(parseBool(data["isOpen"]));
      }));

      // - on incoming message
      api?.on(_incomingMessage, allowInterop((message) {
        final data = {
          'senderId': !kReleaseMode ? message.from : '?',
          'nick': !kReleaseMode ? message.nick : '?',
          'isPrivate': !kReleaseMode ? message.privateMessage : false,
          'message': !kReleaseMode ? message.message : '?',
          'timestamp': DateTime.now().toUtc(),
        };
        listener.onChatMessageReceived?.call(
          data["senderId"]?.toString() ?? '?',
          data["message"]?.toString() ?? '?',
          parseBool(data["isPrivate"]),
          data["timestamp"].toString(),
        );
      }));

      // - on audio mute status changed
      api?.on(_audioMuteStatusChanged, allowInterop((message) {
        final data = {'muted': !kReleaseMode ? message.muted : false};
        listener.onAudioMutedChanged?.call(parseBool(data["muted"]));
      }));

      // - on video mute status changed
      api?.on(_videoMuteStatusChanged, allowInterop((message) {
        final data = {'muted': !kReleaseMode ? message.muted : false};
        listener.onVideoMutedChanged?.call(parseBool(data["muted"], isVideoMutedChanged: true));
      }));

      // - on screen sharing status changed
      api?.on(_screenSharingStatusChanged, allowInterop((message) {
        final data = {
          'sharing': !kReleaseMode ? message.on : false,
          'details': !kReleaseMode ? message.details : {},
          'participantId': !kReleaseMode ? message.id : '?',
        };
        listener.onScreenShareToggled?.call(data["participantId"]?.toString() ?? '?', parseBool(data["sharing"]));
      }));

      // - on feedback submitted
      api?.on(_feedbackSubmitted, allowInterop((message) {
        final data = {"error": !kReleaseMode ? message.error : '?'};
        listener.onError?.call(data["error"]?.toString() ?? "?");
      }));

      // add generic listener
      _addGenericListeners(listener);

      // force to dispose view when close meeting. it's needed to create another room in same view without reload it
      api?.on(_readyToClose, allowInterop((message) {
        listener.onClosed?.call();
        api?.dispose();
      }));
    }

    return JitsiMeetingResponse(isSuccess: true);
  }

  // add generic lister over current session
  _addGenericListeners(JitsiMeetingListener listener) {
    if (api == null) {
      debug_print("jistsi instance not exists event can't be attached");
      return;
    }
    debug_print("genericListeners ${listener.genericListeners}");
    if (listener.genericListeners != null) {
      listener.genericListeners?.forEach((item) {
        debug_print("eventName ${item.eventName}");
        api?.on(item.eventName, allowInterop(item.callback));
      });
    }
  }

  @override
  void executeCommand(String command, List<String> args) => api?.executeCommand(command, args);

  closeMeeting() {
    debug_print("closing the meeting");
    api?.dispose();
    api = null;
  }

  /// Adds a JitsiMeetingListener that will broadcast conference events
  addListener(JitsiMeetingListener jitsiMeetingListener) {
    debug_print("adding listeners");
    _addGenericListeners(jitsiMeetingListener);
  }

  /// Remove JitsiListener - remove all list of listeners bassed on event name
  removeListener(JitsiMeetingListener listner) {
    debug_print("removing listeners");
    Set<String> listeners = {};
    if (listner.onConferenceJoined != null) listeners.add(_videoConferenceJoined);
    if (listner.onConferenceTerminated != null) listeners.add(_videoConferenceLeft);
    listeners.addAll(listner.genericListeners?.map((l) => l.eventName) ?? []);
    api?.removeEventListener(listeners.toList());
  }

  /// Removes all JitsiMeetingListeners - not used for web
  removeAllListeners() {}

  /// Initialize
  void initialize() {}

  @override
  Widget buildView(List<String> extraJS) {
    // ignore: undefined_prefixed_name

    ui.platformViewRegistry.registerViewFactory(_view_id, (int viewId) {
      final div = html.DivElement()
        ..id = _section_id
        ..style.width = '100%'
        ..style.height = '100%';
      return div;
    });
    // add extraJS only once
    // - this validation is needed because the view can be rebuileded several times
    if (!extraJSAdded) {
      _setupExtraScripts(extraJS);
      extraJSAdded = true;
    }

    return HtmlElementView(viewType: _view_id);
  }

  // setup extra JS Scripts
  void _setupExtraScripts(List<String> extraJS) {
    extraJS.forEach((element) {
      RegExp regExp = RegExp(r"<script[^>]*>(.*?)</script[^>]*>");
      if (regExp.hasMatch(element)) {
        final html.NodeValidatorBuilder validator = html.NodeValidatorBuilder.common()
          ..allowElement('script', attributes: ['type', 'crossorigin', 'integrity', 'src']);
        debug_print("ADD script $element");
        html.Element script = html.Element.html(element, validator: validator);
        html.querySelector('head')?.children.add(script);
        // html.querySelector('head').appendHtml(element, validator: validator);
      } else {
        debug_print("$element is not a valid script");
      }
    });
  }

  // Setup the `JitsiMeetExternalAPI` JS script
  void _setupScripts() {
    final tags = html.querySelector('head')?.children;
    final script_content = _clientJs(attach_element_id: _section_id);
    if (tags != null && !tags.any((e) => e.innerText == script_content)) {
      final script = html.ScriptElement()..appendText(script_content);
      tags.add(script);
    }
  }

  // -- Script to allow Jitsi interaction
  // To allow Flutter interact with `JitsiMeetExternalAPI`
  // extends and override the constructor is needed
  static String _clientJs({required String attach_element_id}) => """
class JitsiMeetAPI extends JitsiMeetExternalAPI {
  constructor(domain, options) {
    const _options = JSON.parse(options);

    // set default width and height
    _options.width = _options.width || '100%';
    _options.height = _options.height || '100%';

    // add it to specific parent node
    _options.parentNode = document.querySelector("#$attach_element_id");

    // call parent constructor
    super(domain, _options);
  }
}
// export it
const jitsi = { JitsiMeetAPI };
""";
}

/// Utility functions
/// -- debug print
void debug_print(String message) => debugPrint("[jitsi-meet-plugin] - $message");

/// -- parse bool
/// Required because Android returns boolean values as Strings and iOS SDK returns boolean values as Booleans.
/// (Making this an extension does not work, because of dynamic.)
bool parseBool(dynamic value, {bool isVideoMutedChanged = false}) {
  if (value is bool) return value;
  if (isVideoMutedChanged && value is String) return value != '0.0';
  if (value is String) return value == 'true';
  if (value is num) return value != 0;
  throw ArgumentError('Unsupported type: $value');
}
