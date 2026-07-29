package com.wildkernels.ksutoast

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import android.net.LocalSocket
import android.net.LocalSocketAddress

/** Base notification ID — offset by UID for uniqueness */
const val NOTIF_ID_BASE = 1000

/**
 * Foreground service that connects to the ksu-toastd daemon's APK socket,
 * receives root requests, and posts interactive notifications.
 *
 * No root required — connects as a regular Android app to a world-readable
 * Unix socket created by the daemon.
 */
class MainService : Service() {

    private val CHANNEL_ID = "ksu_toast_requests"
    private val NOTIF_ID_SERVICE = 1

    private var running = true

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildServiceNotification()
        startForeground(NOTIF_ID_SERVICE, notification)

        Thread({ connectToDaemon() }, "ksu-toast-client").start()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.channel_name),
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = getString(R.string.channel_desc)
        }
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    private fun buildServiceNotification(): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.service_notification))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }

    /**
     * Connects to the daemon's APK socket as a client and listens
     * for incoming root request messages.
     *
     * The daemon sends: REQUEST <req_id> <uid> <app_name>\n
     * We post a notification, and when the user taps a button,
     * NotificationActionReceiver sends the response back.
     */
    private fun connectToDaemon() {
        // Abstract socket — matches daemon's @ksu-toast-apk
        // No SELinux file context issues (no filesystem file created)
        val socketName = "ksu-toast-apk"
        val fileSocketPath = "/data/adb/ksu-toast/apk.sock"
        var attemptCount = 0

        // Retry loop — daemon might not be ready yet at boot
        while (running) {
            try {
                attemptCount++
                val socket = LocalSocket()

                // Try abstract socket first (no SELinux), fall back to filesystem
                try {
                    socket.connect(LocalSocketAddress(socketName, LocalSocketAddress.Namespace.ABSTRACT))
                    writeStatus("connected_abstract_$attemptCount")
                } catch (_: Exception) {
                    socket.connect(LocalSocketAddress(fileSocketPath, LocalSocketAddress.Namespace.FILESYSTEM))
                    writeStatus("connected_filesystem_$attemptCount")
                }

                val reader = BufferedReader(InputStreamReader(socket.inputStream))
                val writer = PrintWriter(socket.outputStream, true)

                while (running) {
                    val line = reader.readLine() ?: break
                    handleRequest(line, writer)
                }

                socket.close()
            } catch (e: Exception) {
                if (!running) break
                val msg = e.message ?: e.javaClass.simpleName
                writeStatus("retry_${attemptCount}_${msg.take(40)}")
                // Daemon socket not ready yet — retry in 3 seconds
                try { Thread.sleep(3000) } catch (_: InterruptedException) { break }
            }
        }
    }

    /** Write a status line to debug file */
    private fun writeStatus(msg: String) {
        try {
            java.io.File("/data/local/tmp/ksu-toast-apk-status.txt").appendText("$msg\n")
        } catch (_: Exception) {}
    }

    /**
     * Parse a REQUEST line from the daemon and post a notification.
     *
     * Format: REQUEST <req_id> <uid> <app_name>
     */
    @Suppress("DEPRECATION")
    private fun handleRequest(line: String, writer: PrintWriter) {
        val parts = line.split(" ")
        if (parts.size < 3 || parts[0] != "REQUEST") return

        val reqId = parts[1]
        val uid = parts[2].toIntOrNull() ?: return
        val appName = if (parts.size > 3) parts.drop(3).joinToString(" ") else "unknown"

        // Store writer mapped by reqId so the broadcast receiver can respond
        PendingRequest.store(reqId, writer)

        val intent = Intent(this, NotificationActionReceiver::class.java).apply {
            putExtra("req_id", reqId)
            putExtra("uid", uid)
            putExtra("app_name", appName)
        }

        val grantIntent = PendingIntent.getBroadcast(
            this, uid * 3 + 0,
            (intent.clone() as Intent).apply { putExtra("action", "GRANT") },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val denyIntent = PendingIntent.getBroadcast(
            this, uid * 3 + 1,
            (intent.clone() as Intent).apply { putExtra("action", "DENY") },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val ignoreIntent = PendingIntent.getBroadcast(
            this, uid * 3 + 2,
            (intent.clone() as Intent).apply { putExtra("action", "IGNORE") },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.root_request_title))
            .setContentText(getString(R.string.root_request_text, appName))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_EVENT)
            .addAction(0, getString(R.string.grant), grantIntent)
            .addAction(0, getString(R.string.deny), denyIntent)
            .addAction(0, getString(R.string.ignore), ignoreIntent)
            .build()

        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID_BASE + uid, notification)
    }
}
