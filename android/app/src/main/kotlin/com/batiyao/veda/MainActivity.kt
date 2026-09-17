package com.batiyao.veda

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The activity the recitation's media session needs, and the permission its
 * notification needs.
 *
 * It must extend AudioServiceActivity: audio_service hands the notification's
 * buttons back through this activity's engine, and a plain FlutterActivity
 * makes AudioService.init throw "the Activity class declared in your
 * AndroidManifest.xml is wrong" — at startup, where nobody is looking, leaving
 * an app with no session, no permission prompt and no notification, and no
 * sign of why.
 *
 * From Android 13 a media notification does not appear without
 * POST_NOTIFICATIONS — no error, nothing in the log, exactly as it looks when
 * you have forgotten to declare it. Fifteen lines here rather than a
 * dependency that would drag the whole app's compileSdk forward for one
 * permission dialog.
 */
class MainActivity : AudioServiceActivity() {
    private val channel = "com.batiyao.veda/notifications"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "request" -> result.success(requestNotifications())
                    // The panchang needs to know where the phone is, and the
                    // timezone says so without a location permission.
                    "timezone" -> result.success(java.util.TimeZone.getDefault().id)
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
