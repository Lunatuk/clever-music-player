# just_audio_windows

The windows implementation of [`just_audio`](https://pub.dev/packages/just_audio). Implemented using [Windows' Media Player](https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/play-audio-and-video-with-mediaplayer)

## Features

| Feature                        |   Windows    | Description                                                                                                                                                     |
| ------------------------------ | :----------: | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| read from URL                  |      ✅      |                                                                                                                                                                 |
| read from file                 |      ✅      |                                                                                                                                                                 |
| read from asset                |      ✅      |                                                                                                                                                                 |
| read from byte stream          | (not tested) |                                                                                                                                                                 |
| request headers                |              |                                                                                                                                                                 |
| DASH                           |      ✅      | [Dash profile support](https://docs.microsoft.com/en-us/windows/uwp/audio-video-camera/dash-profile-support)                                                    |
| HLS                            |      ✅      | [Hsl tag support](https://docs.microsoft.com/en-us/windows/uwp/audio-video-camera/hls-tag-support)                                                              |
| ICY metadata                   |              |                                                                                                                                                                 |
| buffer status/position         |      ✅      |                                                                                                                                                                 |
| play/pause/seek                |      ✅      |                                                                                                                                                                 |
| set volume/speed               |      ✅      |                                                                                                                                                                 |
| clip audio                     |              |                                                                                                                                                                 |
| playlists                      |      ✅      | [Playlists](https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/media-playback-with-mediasource#play-a-list-of-media-items-with-mediaplaybacklist) |
| looping/shuffling              |      ✅      |                                                                                                                                                                 |
| compose audio                  |              |                                                                                                                                                                 |
| gapless playback               |      ✅      |                                                                                                                                                                 |
| report player errors           |      ✅      |                                                                                                                                                                 |
| handle phonecall interruptions |              |                                                                                                                                                                 |
| buffering/loading options      |              |                                                                                                                                                                 |
| set pitch                      |      ✅      |                                                                                                                                                                 |
| skip silence                   |              |                                                                                                                                                                 |
| equalizer                      |              |                                                                                                                                                                 |
| volume boost                   |              |                                                                                                                                                                 |

## Player error codes

- `unknown`
- `abort`
- `networkError`
- `decodingError`
- `sourceNotSupported`


## Local first-play fix

This vendored adapter leaves the requested `playing` flag to just_audio.
WinRT Opening/Buffering and a late Paused event during preload are processing
states, not user transport commands. Publishing `playing: false` for them can
cancel a cold play while audio-session activation is pending, before native
`MediaPlayer.Play` is called. Native settings still report volume, rate, loop and
shuffle; playback events still report processing state and timeline. The app's
SMTC service owns media keys and sends play/pause through the shared Dart player.

`tool/check_windows_audio_contract.ps1` compiles the same native payload builder
used by this plugin and verifies the fixture consumed by
`test/windows_first_play_protocol_test.dart`. That test drives the installed
just_audio library through method/event channels and deterministically delivers
late preparation data during the first audio-session activation. It verifies
one-click play and subsequent pause/resume. Windows CI runs both checks; real
WinRT sound output remains a targeted manual check.
