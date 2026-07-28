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
import java.net.ServerSocket
import java.net.Socket

/**
 * Foreground service that listens on a Unix socket for root requests
 * from ksu-toastd and posts interactive notifications.
 *
 * The daemon connects and sends:
 *   REQUEST <req_id> <uid> <app_name>\n
 *
 * The user taps a notification action button, which triggers
 * NotificationActionReceiver to send the response back.
 */
class MainService : Service() {

    private val CHANNEL_ID = "ksu_toast_requests"
    private val NOTIF_ID_SERVICE = 1
    private val NOTIF_ID_BASE = 1000 // + uid for uniqueness

    private var running = true
    private var serverSocket: ServerSocket? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildServiceNotification()
        startForeground(NOTIF_ID_SERVICE, notification)

        // Start listening in a background thread
        Thread({ listenForRequests() }, "ksu-toast-listener").start()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        serverSocket?.close()
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
     * Listens on the APK socket for incoming root requests from ksu-toastd.
     */
    private fun listenForRequests() {
        val socketPath = "/data/adb/ksu-toast/apk.sock"

        try {
            // Bind to the Unix socket
            val local = android.net.LocalServerSocket(socketPath)
            serverSocket = null // We use LocalServerSocket, not ServerSocket
            running = true

            while (running) {
                try {
                    val client = local.accept()
                    handleClient(client)
                } catch (e: Exception) {
                    if (running) {
                        // Ignore transient accept errors
                    }
                }
            }

            local.close()
        } catch (e: Exception) {
            // Socket already exists or other error
            // Try connecting as a client instead (retry loop)
            retryConnectToDaemon()
        }
    }

    /**
     * If we couldn't create the server socket (daemon beat us to it,
     * or permissions), connect as a client to an already-running APK
     * (only one instance needed).
     */
    private fun retryConnectToDaemon() {
        // Even as a client, we still need the daemon to tell us about requests.
        // For now, this means another instance of the APK already has the socket.
        // We just become a standby instance - our service notification stays up.
    }

    /**
     * Handle an incoming connection from ksu-toastd.
     * Format: REQUEST <req_id> <uid> <app_name>\n
     */
    private fun handleClient(client: android.net.LocalSocket) {
        try {
            val reader = BufferedReader(InputStreamReader(client.inputStream))
            val writer = PrintWriter(client.outputStream, true)

            val line = reader.readLine() ?: return
            val parts = line.split(" ")

            if (parts.size >= 3 && parts[0] == "REQUEST") {
                val reqId = parts[1]
                val uid = parts[2].toIntOrNull() ?: return
                val appName = if (parts.size > 3) parts.drop(3).joinToString(" ") else "unknown"

                showNotification(reqId, uid, appName, writer)
            }
        } catch (_: Exception) {
        } finally {
            try { client.close() } catch (_: Exception) {}
        }
    }

    /**
     * Post a notification with Grant/Deny/Ignore actions.
     * The PendingIntent carries the request details so
     * NotificationActionReceiver can respond.
     */
    private fun showNotification(reqId: String, uid: Int, appName: String, writer: PrintWriter) {
        // Store the writer so the broadcast receiver can access it
        PendingRequest.store(reqId, uid, writer)

        val intent = Intent(this, NotificationActionReceiver::class.java).apply {
            putExtra("req_id", reqId)
            putExtra("uid", uid)
            putExtra("app_name", appName)
            // Use unique action for each notification to avoid intent collisions
            action = "com.wildkernels.ksutoast.ACTION_RESPOND_$reqId"
        }

        val grantIntent = PendingIntent.getBroadcast(
            this, uid * 3 + 0,
            intent.clonePacket().apply { putExtra("action", "GRANT") },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val denyIntent = PendingIntent.getBroadcast(
            this, uid * 3 + 1,
            intent.clonePacket().apply { putExtra("action", "DENY") },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val ignoreIntent = PendingIntent.getBroadcast(
            this, uid * 3 + 2,
            intent.clonePacket().apply { putExtra("action", "IGNORE") },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.root_request_title))
            .setContentText(getString(R.string.root_request_text, appName))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_EVENT)
            .setPriority(Notification.PRIORITY_HIGH)
            .addAction(0, getString(R.string.grant), grantIntent)
            .addAction(0, getString(R.string.deny), denyIntent)
            .addAction(0, getString(R.string.ignore), ignoreIntent)
            .build()

        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID_BASE + uid, notification)
    }
}
