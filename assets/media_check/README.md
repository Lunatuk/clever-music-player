These are generated test signals and solid colour images, not music recordings.
The player uses them only for an explicit local qualification; nothing is
imported into the library or sent over the network. No third-party audio/art.

Audio: 440/660 Hz sines, 48000 Hz stereo, 0.6 seconds. FLAC is 24-bit.
Generated with FFmpeg:

```
ffmpeg -f lavfi -i "aevalsrc=0.05*sin(2*PI*440*t)|0.05*sin(2*PI*660*t):s=48000:d=0.6" -c:a libmp3lame -b:a 192k -map_metadata -1 tone.mp3
ffmpeg -f lavfi -i "aevalsrc=0.05*sin(2*PI*440*t)|0.05*sin(2*PI*660*t):s=48000:d=0.6" -c:a aac -b:a 128k -map_metadata -1 tone.m4a
ffmpeg -f lavfi -i "aevalsrc=0.05*sin(2*PI*440*t)|0.05*sin(2*PI*660*t):s=48000:d=0.6" -c:a flac -sample_fmt s32 -map_metadata -1 tone.flac
```

PNG: RGB (40,120,200), 32x32. JPEG: RGB (80,160,40), 32x32. Generated with
Pillow Image.new/save, without external images, profiles or text.
