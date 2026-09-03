package com.johngalt.flutter_ai_communications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class ScreenCaptureService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val label = applicationInfo.loadLabel(packageManager).toString()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    "fac-screen",
                    label,
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val notification =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, "fac-screen")
                    .setSmallIcon(android.R.drawable.presence_video_online)
                    .setContentTitle(label)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
                    .setSmallIcon(android.R.drawable.presence_video_online)
                    .setContentTitle(label)
                    .build()
            }
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                0xFAC4,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(0xFAC4, notification)
        }
        return START_STICKY
    }
}
