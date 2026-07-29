package com.wildkernels.ksutoast

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Launcher activity — invisible, immediately starts the foreground
 * service and finishes. Required because Android 12+ restricts
 * background-start of foreground services. Starting an activity
 * first (even one that immediately finishes) satisfies the
 * "user launched app" requirement for foreground service.
 */
class LauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Start the foreground service
        val intent = Intent(this, MainService::class.java)
        startForegroundService(intent)

        // Finish immediately — no UI needed
        finish()
    }
}
