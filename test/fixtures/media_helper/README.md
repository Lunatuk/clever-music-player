# Synthetic media helper fixtures

Created for this repository with FFmpeg 7.1 (developer Gyan full build).
No recordings, downloaded music or account data. These generated 440 Hz tones
and solid-colour pictures are dedicated to the public domain (CC0-1.0).
Only fixture generation uses audio encoders; the production helper does not.

Reproduce in an empty directory (each command writes a new file):

```text
ffmpeg -v error -nostdin -f lavfi -i sine=frequency=440:sample_rate=48000:duration=2 -map_metadata -1 -c:a libmp3lame -b:a 320k tone.mp3
ffmpeg -v error -nostdin -f lavfi -i sine=frequency=440:sample_rate=48000:duration=2 -map_metadata -1 -c:a aac -b:a 256k tone.m4a
ffmpeg -v error -nostdin -f lavfi -i sine=frequency=440:sample_rate=48000:duration=2 -map_metadata -1 -c:a flac tone.flac
ffmpeg -v error -nostdin -f lavfi -i color=c=blue:s=16x16 -frames:v 1 -threads 1 cover.png
ffmpeg -v error -nostdin -f lavfi -i color=c=red:s=16x16 -frames:v 1 -threads 1 cover.jpg
```

`tool/check_bundled_media_helper.dart <bundle> <this-directory>` performs real
offline tag/cover/stream-copy/decode/hash checks with the candidate helper.
The fixed fixtures allow CI to use a minimal helper without fetching a second,
unqualified full FFmpeg build. They are test inputs, not Flutter runtime assets.
