package com.johngalt.flutter_ai_communications

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.os.Build
import java.util.concurrent.atomic.AtomicBoolean

/// System-audio loopback for Include sound. Bytes stay off the mic Capture
/// stream. Mute does not stop this graph.
internal class AndroidPlaybackCapture {
    private var record: AudioRecord? = null
    private var drain: Thread? = null
    private val running = AtomicBoolean(false)

    fun start(projection: MediaProjection): Boolean {
        stop()
        if (Build.VERSION.SDK_INT < 29) {
            return false
        }
        val config =
            AudioPlaybackCaptureConfiguration.Builder(projection)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()
        val format =
            AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(48_000)
                .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                .build()
        val min = AudioRecord.getMinBufferSize(48_000, format.channelMask, format.encoding)
        if (min <= 0) {
            return false
        }
        val created =
            try {
                AudioRecord.Builder()
                    .setAudioFormat(format)
                    .setBufferSizeInBytes(min * 2)
                    .setAudioPlaybackCaptureConfig(config)
                    .build()
            } catch (_: SecurityException) {
                return false
            }
        if (created.state != AudioRecord.STATE_INITIALIZED) {
            created.release()
            return false
        }
        try {
            created.startRecording()
        } catch (_: IllegalStateException) {
            created.release()
            return false
        }
        record = created
        running.set(true)
        drain =
            Thread({
                val buffer = ByteArray(min)
                while (running.get()) {
                    val live = record ?: break
                    val n = live.read(buffer, 0, buffer.size)
                    if (n < 0) {
                        break
                    }
                    if (n == 0) {
                        try {
                            Thread.sleep(10)
                        } catch (_: InterruptedException) {
                            Thread.currentThread().interrupt()
                            break
                        }
                    }
                }
            }, "fac-playback-capture").apply {
                isDaemon = true
                start()
            }
        return true
    }

    fun stop() {
        running.set(false)
        val live = record
        record = null
        if (live != null) {
            try {
                live.stop()
            } catch (_: IllegalStateException) {
            }
            live.release()
        }
        try {
            drain?.join(250)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        drain = null
    }
}
