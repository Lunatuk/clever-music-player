# Local file ownership and artist roles fixes

This is the previously installed `audio_metadata_reader` 1.6.0 source snapshot.
`SOURCE_SNAPSHOT.json` records hashes before the patch; the original LICENSE is
retained. The shared pub cache is unchanged.

`readMetadata` and `readAllMetadata` now own their opened file through
`OwnedFileReader` and close it in `finally`. Some container parsers close on
success (or in their own finally), whereas failed format probes and failed FLAC
picture parsing could leave an opened reader. The owner makes close idempotent
without depending on exception-message matching. The initial ownership patch did not change parsing/tag mapping; the package 33 changes are described below.

Regression coverage in the app uses actual parser calls: valid tags/cover bytes,
malformed image with no-image retry, unsupported input, and immediate Windows file
deletion after return. Update this local override deliberately when upgrading.

Package 33 keeps the main track artist separate from the album artist.
Generic AudioMetadata now exposes nullable albumArtist. MP3 prefers TPE1 for
artist and exposes TPE2 separately, retaining TPE2 as fallback when TPE1 is
absent. MP4 reads aART independently from ©ART, with album-only fallback.
Vorbis comments keep ARTIST and ALBUMARTIST/ALBUM_ARTIST/ALBUM ARTIST in separate
lists, forwarded for FLAC/OGG; APE forwards its existing albumArtist field.
The app's background reader transfers the field without a database migration.
Parser-only independent fixtures and generated native files check both artist
roles, field order, fallback and reader disposal. Existing indexed tracks are
not rewritten automatically by this patch.
The FLAC/MP4 serializers retain the newly separate album-artist field.
A discovered FLAC serializer bug is fixed: replacement of the last comment/
picture block previously lost the final-block flag (the copied-block helper
also used 255 instead of bit 128). All emitted blocks now precede one explicit
final empty padding block; STREAMINFO-only input also receives new comments.
Reader closure is guaranteed before an attempted write. Parser fixtures and a
generated FLAC verify valid output and unchanged compressed/decoded audio.
These low-level writers remain in-place APIs; the download preparer uses its
separate, verified FFmpeg output instead.
