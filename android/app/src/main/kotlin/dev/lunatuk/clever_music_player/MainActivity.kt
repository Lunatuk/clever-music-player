package dev.lunatuk.clever_music_player

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/** UI and background media service attach to the same Flutter engine. */
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(AudioDocumentsPlugin::class.java)) {
            flutterEngine.plugins.add(AudioDocumentsPlugin())
        }
        if (!flutterEngine.plugins.has(AudioFingerprintPlugin::class.java)) {
            flutterEngine.plugins.add(AudioFingerprintPlugin())
        }
        if (!flutterEngine.plugins.has(DownloadPublicationPlugin::class.java)) {
            flutterEngine.plugins.add(DownloadPublicationPlugin())
        }
        if (!flutterEngine.plugins.has(PublishedAudioVerifierPlugin::class.java)) {
            flutterEngine.plugins.add(PublishedAudioVerifierPlugin())
        }
    }
}
