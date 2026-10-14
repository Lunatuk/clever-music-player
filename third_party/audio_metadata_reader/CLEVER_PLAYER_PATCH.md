# Local file ownership fix

This is the previously installed `audio_metadata_reader` 1.6.0 source snapshot.
`SOURCE_SNAPSHOT.json` records hashes before the patch; the original LICENSE is
retained. The shared pub cache is unchanged.

`readMetadata` and `readAllMetadata` now own their opened file through
`OwnedFileReader` and close it in `finally`. Some container parsers close on
success (or in their own finally), whereas failed format probes and failed FLAC
picture parsing could leave an opened reader. The owner makes close idempotent
without depending on exception-message matching. Parsing/tag mapping is unchanged.

Regression coverage in the app uses actual parser calls: valid tags/cover bytes,
malformed image with no-image retry, unsupported input, and immediate Windows file
deletion after return. Update this local override deliberately when upgrading.
