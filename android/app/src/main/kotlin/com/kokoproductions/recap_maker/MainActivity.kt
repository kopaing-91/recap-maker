package com.kokoproductions.recap_maker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var videoEngine: VideoEngine

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoEngine = VideoEngine(this)
        videoEngine.setup(flutterEngine.dartExecutor.binaryMessenger)
    }
}
