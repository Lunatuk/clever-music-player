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
    }
}
