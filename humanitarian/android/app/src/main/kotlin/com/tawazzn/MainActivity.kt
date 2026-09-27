package com.easytech.humanitarian

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The app's single Android activity.
 *
 * Besides hosting Flutter it creates the notification channel every push from
 * the backend is posted to. Android 8 (API 26) and later post EVERY
 * notification to a channel, and the channel — not the message — decides
 * whether the phone shows a heads-up banner and makes a sound. A message that
 * names a channel the app never created is dropped into the FCM SDK's own
 * fallback channel, whose importance we cannot raise: the notification lands
 * silently in the shade, which a user experiences as "no notifications
 * arrive".
 *
 * Creating a channel is idempotent — Android ignores a repeat create for an
 * id that already exists, and never lowers a channel the user has adjusted —
 * so doing it on every launch is both safe and the only way an app that was
 * installed before the channel existed gets one.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
    }

    /**
     * Create the high-importance channel the backend's pushes name.
     *
     * The id MUST match, character for character:
     *   - `AndroidChannelID` in backend/internal/notify/fcm.go, which is what
     *     the FCM payload's `android.notification.channel_id` carries, and
     *   - the `default_notification_channel_id` meta-data in AndroidManifest,
     *     which covers any message that arrives without a channel_id.
     *
     * IMPORTANCE_HIGH is deliberate: it is the lowest importance that still
     * produces a heads-up banner, which is what a chat message needs. The user
     * can still turn it down in system settings, and we must not override that
     * — hence the create-only-if-absent behaviour Android gives us for free.
     *
     * No-op below API 26, where channels do not exist and notifications always
     * alert.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.default_notification_channel_id),
            getString(R.string.default_notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.default_notification_channel_description)
            enableVibration(true)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
    }
}
