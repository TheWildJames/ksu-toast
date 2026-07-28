package com.wildkernels.ksutoast

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.PrintWriter

/**
 * Handles notification action button taps (Grant/Deny/Ignore).
 * Sends the response back to ksu-toastd via the stored PrintWriter.
 */
class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val reqId = intent.getStringExtra("req_id") ?: return
        val uid = intent.getIntExtra("uid", -1)
        val action = intent.getStringExtra("action") ?: return

        // Dismiss the notification
        if (uid >= 0) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(MainService.NOTIF_ID_BASE + uid)
        }

        // Send response back to daemon
        val writer = PendingRequest.remove(reqId)
        if (writer != null) {
            writer.println("$action $reqId")
            writer.flush()
            writer.close()
        }
    }
}
