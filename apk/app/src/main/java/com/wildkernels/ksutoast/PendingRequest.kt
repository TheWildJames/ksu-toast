package com.wildkernels.ksutoast

import java.io.PrintWriter
import java.util.concurrent.ConcurrentHashMap

/**
 * Stores pending root request writers so that the NotificationActionReceiver
 * can send responses back to ksu-toastd.
 */
object PendingRequest {
    private val requests = ConcurrentHashMap<String, PrintWriter>()

    fun store(reqId: String, writer: PrintWriter) {
        requests[reqId] = writer
    }

    fun remove(reqId: String): PrintWriter? {
        return requests.remove(reqId)
    }
}
