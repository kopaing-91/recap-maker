package com.kokoproductions.recap_maker

import android.content.ContentValues
import android.graphics.*
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class VideoEngine(private val activity: MainActivity) {
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var cancelled = false
    @Volatile private var currentProcess: Process? = null
    private var progressSink: EventChannel.EventSink? = null

    fun setup(messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, "com.kokoproductions.recap_maker/video")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "probe" -> executor.execute {
                        try {
                            result.success(probe(call.argument<String>("path")!!))
                        } catch (e: Exception) {
                            result.error("PROBE_FAIL", e.message, null)
                        }
                    }
                    "render" -> {
                        cancelled = false
                        executor.execute {
                            try {
                                @Suppress("UNCHECKED_CAST")
                                val out = render(call.arguments as Map<String, Any>)
                                result.success(out)
                            } catch (e: Exception) {
                                if (cancelled) result.error("CANCELLED", "cancelled", null)
                                else result.error("RENDER_FAIL", e.message, null)
                            }
                        }
                    }
                    "cancel" -> {
                        cancelled = true
                        currentProcess?.destroy()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(messenger, "com.kokoproductions.recap_maker/videoProgress")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    progressSink = sink
                }
                override fun onCancel(args: Any?) { progressSink = null }
            })
        MethodChannel(messenger, "com.kokoproductions.recap_maker/media")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveToGallery") {
                    try {
                        result.success(saveToGallery(call.argument<String>("path")!!))
                    } catch (e: Exception) {
                        result.error("SAVE_FAIL", e.message, null)
                    }
                } else result.notImplemented()
            }
    }

    // ---------- bundled ffmpeg binary ----------
    // Shipped as libffmpeg.so in jniLibs so it lands in the app's native
    // library dir (executable). We do NOT copy to filesDir: Android 10+
    // blocks execution from there (SELinux), causing "Permission denied".
    private val ffmpeg: String by lazy {
        val libFile = File(activity.applicationInfo.nativeLibraryDir, "libffmpeg.so")
        if (!libFile.exists()) {
            // Fallback: old installs may still have the assets copy
            val out = File(activity.filesDir, "ffmpeg")
            if (!out.exists() || out.length() < 1000000) {
                val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
                val assetName = if (abi.contains("64")) "ffmpeg-arm64" else "ffmpeg-arm32"
                activity.assets.open(assetName).use { inp ->
                    out.outputStream().use { inp.copyTo(it) }
                }
            }
            if (!out.canExecute()) {
                out.setExecutable(true)
                try {
                    Runtime.getRuntime().exec(arrayOf("chmod", "755", out.absolutePath)).waitFor()
                } catch (e: Exception) { /* best effort */ }
            }
            return@lazy out.absolutePath
        }
        libFile.absolutePath
    }

    private fun ffprobeJson(path: String): String {
        // use ffmpeg -i to get info (we bundle only ffmpeg, not ffprobe)
        val pb = ProcessBuilder(ffmpeg, "-hide_banner", "-i", path)
        pb.redirectErrorStream(true)
        val p = pb.start()
        val out = p.inputStream.bufferedReader().readText()
        p.waitFor()
        return out
    }

    private fun probe(path: String): Map<String, Any> {
        val out = ffprobeJson(path)
        val dur = Regex("Duration: (\\d+):(\\d+):([\\d.]+)").find(out)
        var secs = 0.0
        if (dur != null) {
            secs = dur.groupValues[1].toDouble() * 3600 +
                   dur.groupValues[2].toDouble() * 60 +
                   dur.groupValues[3].toDouble()
        }
        val vs = Regex("Video:.*? (\\d+)x(\\d+)").find(out)
        return mapOf(
            "durationSec" to secs,
            "width" to (vs?.groupValues?.get(1)?.toIntOrNull() ?: 0),
            "height" to (vs?.groupValues?.get(2)?.toIntOrNull() ?: 0)
        )
    }

    // ---------- command execution ----------
    private fun emit(progress: Double, stage: String) {
        activity.runOnUiThread {
            progressSink?.success(mapOf("progress" to progress, "stage" to stage))
        }
    }

    private fun sh(cmd: List<String>, stage: String) {
        if (cancelled) throw Exception("cancelled")
        val pb = ProcessBuilder(cmd)
        pb.redirectErrorStream(true)
        val p = pb.start()
        currentProcess = p
        val log = StringBuilder()
        p.inputStream.bufferedReader().forEachLine { log.appendLine(it) }
        val rc = p.waitFor()
        currentProcess = null
        if (cancelled) throw Exception("cancelled")
        if (rc != 0) throw Exception("ffmpeg failed ($stage): ${log.takeLast(500)}")
    }

    private fun shTracked(cmd: List<String>, stage: String,
                          base: Double, span: Double, expectedMs: Long) {
        if (cancelled) throw Exception("cancelled")
        val pb = ProcessBuilder(cmd)
        pb.redirectErrorStream(true)
        val p = pb.start()
        currentProcess = p
        val durRe = Regex("time=(\\d+):(\\d+):([\\d.]+)")
        p.inputStream.bufferedReader().forEachLine { line ->
            durRe.find(line)?.let { m ->
                val ms = (m.groupValues[1].toLong() * 3600 +
                         m.groupValues[2].toLong() * 60 +
                         m.groupValues[3].toDouble()) * 1000
                emit(base + span * (ms / expectedMs).coerceIn(0.0, 1.0), stage)
            }
            if (cancelled) p.destroy()
        }
        val rc = p.waitFor()
        currentProcess = null
        if (cancelled) throw Exception("cancelled")
        if (rc != 0) throw Exception("ffmpeg failed ($stage)")
    }

    // ---------- render ----------
    data class Seg(val start: Double, val dur: Double, val move: Int,
                  val freeze: Double, val scriptIndex: Int)

    private fun render(args: Map<String, Any>): String {
        val source = args["sourcePath"] as String
        val workId = args["workDir"] as String
        @Suppress("UNCHECKED_CAST")
        val segMaps = args["segments"] as List<Map<String, Any>>
        @Suppress("UNCHECKED_CAST")
        val narrationPaths = args["narrationPaths"] as List<String>
        @Suppress("UNCHECKED_CAST")
        val texts = args["scriptTexts"] as List<String>
        @Suppress("UNCHECKED_CAST")
        val speeds = args["speeds"] as List<Double>
        @Suppress("UNCHECKED_CAST")
        val tempoFix = (args["tempoFix"] as? List<Boolean>)
            ?: List(texts.size) { false }

        val segs = segMaps.map {
            Seg((it["start"] as Number).toDouble(), (it["dur"] as Number).toDouble(),
                (it["move"] as Number).toInt(), (it["freeze"] as Number).toDouble(),
                (it["scriptIndex"] as Number).toInt())
        }
        val work = File(activity.cacheDir, "render_$workId").apply { mkdirs() }
        val totalSec = segs.sumOf { it.dur + it.freeze }
        val ff = ffmpeg

        emit(0.0, "Clip တွေ ထုတ်နေတယ်...")
        val listSb = StringBuilder()
        segs.forEachIndexed { i, s ->
            val segFile = File(work, "seg_%03d.mp4".format(i))
            val frzFile = File(work, "frz_%03d.mp4".format(i))
            shTracked(
                listOf(ff, "-ss", s.start.toString(), "-i", source,
                    "-t", s.dur.toString(), "-vf", cameraFilter(s.move, s.dur),
                    "-an", "-r", "30", "-c:v", videoCodec, "-b:v", "5M",
                    "-y", segFile.absolutePath),
                "Clip ${i + 1}/${segs.size}", 0.0, 0.45,
                (s.dur * 1000).toLong()
            )
            sh(listOf(ff, "-sseof", "-0.1", "-i", segFile.absolutePath,
                "-vframes", "1", "-y", "${work.absolutePath}/last_$i.png"),
                "freeze $i")
            val frames = (s.freeze * 30).toInt()
            sh(listOf(ff, "-loop", "1", "-i", "${work.absolutePath}/last_$i.png",
                "-vf", "zoompan=z='1+0.12*on/$frames':d=$frames:" +
                        "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1280x720:fps=30",
                "-t", s.freeze.toString(), "-c:v", videoCodec, "-b:v", "5M",
                "-y", frzFile.absolutePath),
                "freeze $i")
            listSb.appendLine("file '${segFile.absolutePath}'")
            listSb.appendLine("file '${frzFile.absolutePath}'")
        }
        val concatList = File(work, "list.txt").apply { writeText(listSb.toString()) }

        emit(0.5, "ဆက်နေတယ်...")
        val concatMp4 = File(work, "concat.mp4")
        sh(listOf(ff, "-f", "concat", "-safe", "0", "-i", concatList.absolutePath,
            "-c", "copy", "-y", concatMp4.absolutePath), "concat")

        emit(0.58, "အသံ ပြင်နေတယ်...")
        val fixedPaths = narrationPaths.mapIndexed { i, p ->
            if (tempoFix[i] && speeds[i] != 1.0) {
                val fixed = File(work, "narr_%d.m4a".format(i))
                sh(listOf(ff, "-i", p, "-af", "atempo=${speeds[i]}",
                    "-c:a", "aac", "-b:a", "128k", "-y", fixed.absolutePath),
                    "atempo $i")
                fixed.absolutePath
            } else p
        }
        val audioList = File(work, "alist.txt").apply {
            writeText(fixedPaths.joinToString("\n") { "file '$it'" })
        }
        val narration = File(work, "narration.m4a")
        sh(listOf(ff, "-f", "concat", "-safe", "0", "-i", audioList.absolutePath,
            "-c:a", "aac", "-b:a", "128k", "-y", narration.absolutePath),
            "narration")

        emit(0.66, "စာတန်း ရေးနေတယ်...")
        val subPngs = texts.mapIndexed { i, t ->
            renderSubtitle(t, File(work, "sub_$i.png")) }

        emit(0.7, "အပြီးသတ် ပေါင်းနေတယ်...")
        val cmd = mutableListOf(ff, "-i", concatMp4.absolutePath,
            "-i", narration.absolutePath)
        subPngs.forEach { cmd.addAll(listOf("-i", it.absolutePath)) }

        val lineStart = DoubleArray(texts.size)
        val lineDur = DoubleArray(texts.size)
        var t = 0.0
        for (i in texts.indices) {
            lineStart[i] = t
            val d = segs.filter { it.scriptIndex == i }.sumOf { it.dur + it.freeze }
            lineDur[i] = d
            t += d
        }
        val fc = StringBuilder()
        var last = "0:v"
        subPngs.forEachIndexed { i, _ ->
            val s = lineStart[i]; val e = s + lineDur[i]
            fc.append("[$last][${i + 2}:v]overlay=(W-w)/2:H-h-70:" +
                      "enable='between(t,$s,$e)'[v$i];")
            last = "v$i"
        }
        if (fc.isNotEmpty()) fc.setLength(fc.length - 1)
        if (fc.isNotEmpty()) {
            cmd.addAll(listOf("-filter_complex", fc.toString(),
                "-map", "[$last]"))
        } else {
            cmd.addAll(listOf("-map", "0:v"))
        }
        val outFile = File(activity.filesDir, "recap_${workId}.mp4")
        cmd.addAll(listOf("-map", "1:a", "-c:v", videoCodec, "-b:v", "5M",
            "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
            "-shortest", "-y", outFile.absolutePath))
        shTracked(cmd, "Final", 0.7, 0.3, (totalSec * 1000).toLong())

        emit(1.0, "ပြီးပြီ!")
        return outFile.absolutePath
    }

    private val videoCodec: String by lazy {
        // Prefer libx264 software encoding (reliable on all devices);
        // fall back to h264_mediacodec only if libx264 is missing.
        try {
            val pb = ProcessBuilder(ffmpeg, "-hide_banner", "-h", "encoder=libx264")
            pb.redirectErrorStream(true)
            val p = pb.start()
            val out = p.inputStream.bufferedReader().readText()
            p.waitFor()
            if (out.contains("libx264")) "libx264" else "h264_mediacodec"
        } catch (_: Exception) { "h264_mediacodec" }
    }

    private fun cameraFilter(move: Int, durSec: Double): String {
        val frames = (durSec * 30).toInt()
        val zp = when (move % 4) {
            0 -> "z='min(1+0.18*on/$frames\\,1.18)'"
            1 -> "z='max(1.25-0.20*on/$frames\\,1.05)'"
            2 -> "z=1.3:x='(iw-iw/zoom)*on/$frames'"
            else -> "z=1.3:x='(iw-iw/zoom)*(1-on/$frames)'"
        }
        return "zoompan=$zp:d=$frames:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':" +
               "s=1280x720:fps=30,scale=1280:720:force_original_aspect_ratio=increase," +
               "crop=1280:720"
    }

    private fun renderSubtitle(text: String, out: File): File {
        val W = 1280; val H = 180
        val bmp = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val tf = try {
            Typeface.createFromAsset(activity.assets, "fonts/Padauk-Bold.ttf")
        } catch (_: Exception) { Typeface.DEFAULT_BOLD }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = tf; textSize = 64f; color = Color.WHITE
            textAlign = Paint.Align.CENTER; style = Paint.Style.FILL
            setShadowLayer(8f, 0f, 4f, Color.BLACK)
        }
        val words = text.split(" ")
        val lines = mutableListOf<String>()
        var cur = ""
        for (w in words) {
            val test = if (cur.isEmpty()) w else "$cur $w"
            if (paint.measureText(test) > W - 80 && cur.isNotEmpty()) {
                lines.add(cur); cur = w
            } else cur = test
            if (lines.size == 2) break
        }
        if (cur.isNotEmpty() && lines.size < 2) lines.add(cur)
        val stroke = Paint(paint).apply {
            style = Paint.Style.STROKE; strokeWidth = 6f; color = Color.BLACK
        }
        var y = (H / 2 - (lines.size - 1) * 40).toFloat()
        for (ln in lines) {
            c.drawText(ln, W / 2f, y + 30, stroke)
            c.drawText(ln, W / 2f, y + 30, paint)
            y += 80
        }
        out.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bmp.recycle()
        return out
    }

    private fun saveToGallery(path: String): String {
        val file = File(path)
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_MOVIES + "/RecapMaker")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }
        val resolver = activity.contentResolver
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)!!
        resolver.openOutputStream(uri)!!.use { out ->
            file.inputStream().use { it.copyTo(out) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return uri.toString()
    }
}
