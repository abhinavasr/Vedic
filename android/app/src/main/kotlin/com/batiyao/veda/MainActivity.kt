package com.batiyao.veda

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Asking for the one permission the recitation's notification needs.
 *
 * From Android 13 a media notification does not appear without
 * POST_NOTIFICATIONS — no error, nothing in the log, exactly as it looks when
 * you have forgotten to declare it. Fifteen lines here rather than a
 * dependency that would drag the whole app's compileSdk forward for one
 * permission dialog.
 */
class MainActivity : FlutterActivity() {
    private val channel = "com.batiyao.veda/notifications"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "request" -> result.success(requestNotifications())
                    else -> result.notImplemented()
                }
            }
    }

    /** Whether notifications are allowed, asking once if they are not. */
    private fun requestNotifications(): Boolean {
        // Before 13 the permission does not exist and notifications are on.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return true
        // The answer arrives long after this returns. Nothing waits on it:
        // refusing costs the notification and nothing else, and the
        // recitation plays either way.
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            1,
        )
        return false
    }
}
