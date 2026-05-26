import Cocoa
import FlutterMacOS
import MediaPlayer

final class MacosNowPlayingBridge: NSObject, FlutterStreamHandler {
  private static var shared: MacosNowPlayingBridge?

  private let infoCenter = MPNowPlayingInfoCenter.default()
  private let commandCenter = MPRemoteCommandCenter.shared()
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
  private var buttonConfig = ButtonConfig()
  private var playbackStatus = "stopped"
  private var lastTimeline: Timeline?

  static func register(with controller: FlutterViewController) {
    let bridge = MacosNowPlayingBridge()
    let messenger = controller.engine.binaryMessenger
    let methodChannel = FlutterMethodChannel(
      name: "clever_music_player/macos_now_playing",
      binaryMessenger: messenger
    )
    let eventChannel = FlutterEventChannel(
      name: "clever_music_player/macos_now_playing/events",
      binaryMessenger: messenger
    )

    bridge.methodChannel = methodChannel
    bridge.eventChannel = eventChannel
    methodChannel.setMethodCallHandler(bridge.handle)
    eventChannel.setStreamHandler(bridge)
    shared = bridge
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      do {
        switch call.method {
        case "initialize":
          try self.initialize(arguments: call.arguments)
          result(nil)
        case "enable":
          self.applyCommandEnabledState(isEnabled: true)
          result(nil)
        case "disable":
          self.applyCommandEnabledState(isEnabled: false)
          result(nil)
        case "updateMetadata":
          try self.updateMetadata(arguments: call.arguments)
          result(nil)
        case "updateTimeline":
          try self.updateTimeline(arguments: call.arguments)
          result(nil)
        case "clearMetadata":
          self.clearMetadata()
          result(nil)
        case "setPlaybackStatus":
          try self.setPlaybackStatus(arguments: call.arguments)
          result(nil)
        case "dispose":
          self.disposeBridge()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(
          FlutterError(
            code: "macos_now_playing_error",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func initialize(arguments: Any?) throws {
    buttonConfig = try ButtonConfig(arguments: arguments)
    clearCommandTargets()
    registerCommand(commandCenter.playCommand, button: "play")
    registerCommand(commandCenter.pauseCommand, button: "pause")
    registerCommand(commandCenter.nextTrackCommand, button: "next")
    registerCommand(commandCenter.previousTrackCommand, button: "previous")
    registerToggleCommand()
    disableUnsupportedCommands()
    applyCommandEnabledState(isEnabled: true)
    infoCenter.playbackState = .stopped
  }

  private func updateMetadata(arguments: Any?) throws {
    guard let metadata = arguments as? [String: Any] else {
      throw BridgeError.invalidArguments("updateMetadata requires a metadata map.")
    }

    var info = infoCenter.nowPlayingInfo ?? [:]
    setString(metadata["title"], forKey: MPMediaItemPropertyTitle, in: &info)
    setString(metadata["artist"], forKey: MPMediaItemPropertyArtist, in: &info)
    setString(metadata["album"], forKey: MPMediaItemPropertyAlbumTitle, in: &info)
    setString(
      metadata["albumArtist"],
      forKey: MPMediaItemPropertyAlbumArtist,
      in: &info
    )
    info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

    if let artwork = loadArtwork(from: metadata["thumbnail"] as? String) {
      info[MPMediaItemPropertyArtwork] = artwork
    } else {
      info.removeValue(forKey: MPMediaItemPropertyArtwork)
    }

    applyTimeline(to: &info)
    applyPlaybackRate(to: &info)
    infoCenter.nowPlayingInfo = info
  }

  private func updateTimeline(arguments: Any?) throws {
    guard let timeline = Timeline(arguments: arguments) else {
      throw BridgeError.invalidArguments("updateTimeline requires a timeline map.")
    }

    lastTimeline = timeline
    var info = infoCenter.nowPlayingInfo ?? [:]
    applyTimeline(to: &info)
    applyPlaybackRate(to: &info)
    infoCenter.nowPlayingInfo = info
  }

  private func clearMetadata() {
    lastTimeline = nil
    infoCenter.nowPlayingInfo = nil
    infoCenter.playbackState = .stopped
  }

  private func setPlaybackStatus(arguments: Any?) throws {
    guard let status = arguments as? String else {
      throw BridgeError.invalidArguments("setPlaybackStatus requires a status string.")
    }

    playbackStatus = status
    infoCenter.playbackState = nowPlayingState(for: status)

    guard var info = infoCenter.nowPlayingInfo else {
      return
    }
    applyPlaybackRate(to: &info)
    infoCenter.nowPlayingInfo = info
  }

  private func disposeBridge() {
    clearCommandTargets()
    applyCommandEnabledState(isEnabled: false)
    clearMetadata()
    eventSink = nil
  }

  private func registerCommand(_ command: MPRemoteCommand, button: String) {
    let target = command.addTarget { [weak self] _ in
      guard let self, let eventSink = self.eventSink else {
        return .commandFailed
      }

      eventSink(button)
      return .success
    }
    commandTargets.append((command: command, target: target))
  }

  private func registerToggleCommand() {
    let target = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self, let eventSink = self.eventSink else {
        return .commandFailed
      }

      eventSink(self.playbackStatus == "playing" ? "pause" : "play")
      return .success
    }
    commandTargets.append((command: commandCenter.togglePlayPauseCommand, target: target))
  }

  private func clearCommandTargets() {
    for registration in commandTargets {
      registration.command.removeTarget(registration.target)
    }
    commandTargets.removeAll()
  }

  private func applyCommandEnabledState(isEnabled: Bool) {
    commandCenter.playCommand.isEnabled = isEnabled && buttonConfig.playEnabled
    commandCenter.pauseCommand.isEnabled = isEnabled && buttonConfig.pauseEnabled
    commandCenter.togglePlayPauseCommand.isEnabled =
      isEnabled && (buttonConfig.playEnabled || buttonConfig.pauseEnabled)
    commandCenter.nextTrackCommand.isEnabled = isEnabled && buttonConfig.nextEnabled
    commandCenter.previousTrackCommand.isEnabled =
      isEnabled && buttonConfig.previousEnabled
  }

  private func disableUnsupportedCommands() {
    commandCenter.stopCommand.isEnabled = false
    commandCenter.changePlaybackRateCommand.isEnabled = false
    commandCenter.changeRepeatModeCommand.isEnabled = false
    commandCenter.changeShuffleModeCommand.isEnabled = false
    commandCenter.skipForwardCommand.isEnabled = false
    commandCenter.skipBackwardCommand.isEnabled = false
    commandCenter.seekForwardCommand.isEnabled = false
    commandCenter.seekBackwardCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    commandCenter.ratingCommand.isEnabled = false
    commandCenter.likeCommand.isEnabled = false
    commandCenter.dislikeCommand.isEnabled = false
    commandCenter.bookmarkCommand.isEnabled = false
  }

  private func setString(
    _ value: Any?,
    forKey key: String,
    in info: inout [String: Any]
  ) {
    if let string = value as? String, !string.isEmpty {
      info[key] = string
    } else {
      info.removeValue(forKey: key)
    }
  }

  private func applyTimeline(to info: inout [String: Any]) {
    guard let timeline = lastTimeline else {
      info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
      info.removeValue(forKey: MPNowPlayingInfoPropertyElapsedPlaybackTime)
      return
    }

    let duration = max(0.0, Double(timeline.endMs) / 1000.0)
    let position = max(0.0, Double(timeline.positionMs) / 1000.0)
    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    } else {
      info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
    }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = min(position, duration)
  }

  private func applyPlaybackRate(to info: inout [String: Any]) {
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    info[MPNowPlayingInfoPropertyPlaybackRate] =
      playbackStatus == "playing" ? 1.0 : 0.0
  }

  private func nowPlayingState(for status: String) -> MPNowPlayingPlaybackState {
    switch status {
    case "playing":
      return .playing
    case "paused":
      return .paused
    case "stopped", "closed":
      return .stopped
    default:
      return .unknown
    }
  }

  private func loadArtwork(from thumbnail: String?) -> MPMediaItemArtwork? {
    guard
      let thumbnail,
      let url = URL(string: thumbnail),
      url.isFileURL,
      let image = NSImage(contentsOf: url),
      image.isValid
    else {
      return nil
    }

    return MPMediaItemArtwork(boundsSize: image.size) { _ in
      image
    }
  }
}

private struct ButtonConfig {
  var playEnabled = true
  var pauseEnabled = true
  var stopEnabled = false
  var nextEnabled = true
  var previousEnabled = true
  var fastForwardEnabled = false
  var rewindEnabled = false

  init() {}

  init(arguments: Any?) throws {
    guard let arguments = arguments as? [String: Any] else {
      throw BridgeError.invalidArguments("initialize requires a button config map.")
    }

    playEnabled = arguments["playEnabled"] as? Bool ?? true
    pauseEnabled = arguments["pauseEnabled"] as? Bool ?? true
    stopEnabled = arguments["stopEnabled"] as? Bool ?? false
    nextEnabled = arguments["nextEnabled"] as? Bool ?? true
    previousEnabled = arguments["previousEnabled"] as? Bool ?? true
    fastForwardEnabled = arguments["fastForwardEnabled"] as? Bool ?? false
    rewindEnabled = arguments["rewindEnabled"] as? Bool ?? false
  }
}

private struct Timeline {
  let startMs: Int
  let endMs: Int
  let positionMs: Int
  let minSeekTimeMs: Int
  let maxSeekTimeMs: Int

  init?(arguments: Any?) {
    guard let arguments = arguments as? [String: Any] else {
      return nil
    }

    startMs = arguments["startMs"] as? Int ?? 0
    endMs = arguments["endMs"] as? Int ?? 0
    positionMs = arguments["positionMs"] as? Int ?? 0
    minSeekTimeMs = arguments["minSeekTimeMs"] as? Int ?? 0
    maxSeekTimeMs = arguments["maxSeekTimeMs"] as? Int ?? 0
  }
}

private enum BridgeError: LocalizedError {
  case invalidArguments(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let message):
      return message
    }
  }
}
