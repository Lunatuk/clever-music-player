# Source-comment fixtures

`linked.mp3`, `linked.m4a` and `linked.flac` are synthetic short audio from
`assets/media_check/tone.*`, with the synthetic `assets/media_check/cover.png`.
FFmpeg 7.1.5 remuxed them with `-c copy`, `-map 0:a:0 -map 1:v:0`,
`-disposition:v:0 attached_pic`, title `Source fixture`, artist `Fixture artist`,
album `Fixture album` and comment `https://music.yandex.ru/album/12/track/34`.
MP3 uses `-id3v2_version 3`. No account, remote music or network access is used.

The same files exercise Android JVM positional tag parsing and the existing
desktop reader. Android unit-test resources include this directory; release
APKs do not package these fixtures. Covers and playable audio remain present.
