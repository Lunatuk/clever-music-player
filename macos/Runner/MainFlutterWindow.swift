import Cocoa
import FlutterMacOS
import MediaPlayer

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacosNowPlayingBridge.shared.register(
      with: flutterViewController.registrar(forPlugin: "MacosNowPlayingBridge"))

    super.awakeFromNib()
  }
}

private final class MacosNowPlayingBridge: NSObject, FlutterStreamHandler {
  static let shared = MacosNowPlayingBridge()

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
  private var isInitialized = false

  func register(with registrar: FlutterPluginRegistrar) {
    guard methodChannel == nil else {
      return
    }

    let methodChannel = FlutterMethodChannel(
      name: "clever_music_player/macos_now_playing",
      binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(
      name: "clever_music_player/macos_now_playing_events",
      binaryMessenger: registrar.messenger)

    methodChannel.setMethodCallHandler(handle)
    eventChannel.setStreamHandler(self)

    self.methodChannel = methodChannel
    self.eventChannel = eventChannel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      initializeNowPlaying()
      result(nil)
    case "updateMetadata":
      updateMetadata(call.arguments)
      result(nil)
    case "setPlaybackStatus":
      setPlaybackStatus(call.arguments as? String)
      result(nil)
    case "clearMetadata":
      clearMetadata()
      result(nil)
    case "dispose":
      disposeNowPlaying()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initializeNowPlaying() {
    guard !isInitialized else {
      return
    }

    let center = MPRemoteCommandCenter.shared()
    registerCommand(center.playCommand, eventName: "play")
    registerCommand(center.pauseCommand, eventName: "pause")
    registerTogglePlayPauseCommand(center.togglePlayPauseCommand)
    registerCommand(center.nextTrackCommand, eventName: "next")
    registerCommand(center.previousTrackCommand, eventName: "previous")
    isInitialized = true
  }

  private func disposeNowPlaying() {
    for commandTarget in commandTargets {
      commandTarget.command.removeTarget(commandTarget.target)
      commandTarget.command.isEnabled = false
    }
    commandTargets.removeAll()
    clearMetadata()
    isInitialized = false
  }

  private func updateMetadata(_ arguments: Any?) {
    guard let args = arguments as? [String: Any?] else {
      return
    }

    var info = [String: Any]()
    info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

    if let title = args["title"] as? String {
      info[MPMediaItemPropertyTitle] = title
    }
    if let artist = args["artist"] as? String {
      info[MPMediaItemPropertyArtist] = artist
    }
    if let album = args["album"] as? String {
      info[MPMediaItemPropertyAlbumTitle] = album
    }
    if let albumArtist = args["albumArtist"] as? String {
      info[MPMediaItemPropertyAlbumArtist] = albumArtist
    }
    if let artworkPath = args["artworkPath"] as? String,
       let artwork = loadArtwork(from: artworkPath) {
      info[MPMediaItemPropertyArtwork] = artwork
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func setPlaybackStatus(_ rawStatus: String?) {
    let center = MPNowPlayingInfoCenter.default()
    switch rawStatus {
    case "unknown":
      center.playbackState = .unknown
    case "playing":
      center.playbackState = .playing
    case "paused":
      center.playbackState = .paused
    case "stopped":
      center.playbackState = .stopped
    default:
      center.playbackState = .stopped
    }
  }

  private func clearMetadata() {
    let center = MPNowPlayingInfoCenter.default()
    center.playbackState = .stopped
    center.nowPlayingInfo = nil
  }

  private func registerCommand(_ command: MPRemoteCommand, eventName: String) {
    command.isEnabled = true
    let target = command.addTarget { [weak self] _ in
      self?.eventSink?(eventName)
      return .success
    }
    commandTargets.append((command: command, target: target))
  }

  private func registerTogglePlayPauseCommand(_ command: MPRemoteCommand) {
    command.isEnabled = true
    let target = command.addTarget { [weak self] _ in
      let center = MPNowPlayingInfoCenter.default()
      let eventName = center.playbackState == .playing ? "pause" : "play"
      self?.eventSink?(eventName)
      return .success
    }
    commandTargets.append((command: command, target: target))
  }

  private func loadArtwork(from pathOrUri: String) -> MPMediaItemArtwork? {
    guard let data = loadArtworkData(from: pathOrUri),
          let image = NSImage(data: data) else {
      return nil
    }

    return MPMediaItemArtwork(boundsSize: image.size) { _ in
      return image
    }
  }

  private func loadArtworkData(from pathOrUri: String) -> Data? {
    if pathOrUri.hasPrefix("file://"),
       let url = URL(string: pathOrUri) {
      return try? Data(contentsOf: url)
    }

    let url = URL(fileURLWithPath: pathOrUri)
    return try? Data(contentsOf: url)
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
}
