package br.com.controlfin.app

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.service.notification.NotificationListenerService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** Aberto pelo aviso "Confirme no ControlFin". */
        const val EXTRA_OPEN_INBOX = "open_bank_inbox"
        private const val CHANNEL = "controlfin/bank_notifications"
    }

    private var channel: MethodChannel? = null

    /** O app foi aberto pelo aviso e o Dart ainda não perguntou. */
    private var openInboxPending = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        openInboxPending = intent?.getBooleanExtra(EXTRA_OPEN_INBOX, false) == true
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "listener" to isListenerEnabled(),
                            "post" to canPostNotifications(),
                            "battery" to isIgnoringBattery(),
                        )
                    )
                    "openListenerSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "openBatterySettings" -> {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    }
                    "requestPostPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
                        }
                        result.success(null)
                    }
                    "list" -> result.success(NotificationStore.list(this))
                    "update" -> {
                        val id = call.argument<String>("id")!!
                        val fields = call.argument<Map<String, Any?>>("fields") ?: emptyMap()
                        NotificationStore.update(this, id, fields)
                        result.success(null)
                    }
                    "remove" -> {
                        NotificationStore.remove(this, call.argument<List<String>>("ids") ?: emptyList())
                        result.success(null)
                    }
                    "takeOpenInbox" -> {
                        result.success(openInboxPending)
                        openInboxPending = false
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("erro", e.message, null)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(EXTRA_OPEN_INBOX, false)) {
            channel?.invokeMethod("openInbox", null)
        }
    }

    private fun listenerComponent() = ComponentName(this, BankNotificationListener::class.java)

    private fun isListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        val on = enabled.contains(listenerComponent().flattenToString())
        // A economia de bateria (comum na Samsung) às vezes desliga o serviço:
        // pede para o Android religar.
        if (on && Build.VERSION.SDK_INT >= 24) {
            NotificationListenerService.requestRebind(listenerComponent())
        }
        return on
    }

    private fun canPostNotifications(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    private fun isIgnoringBattery(): Boolean =
        (getSystemService(POWER_SERVICE) as PowerManager)
            .isIgnoringBatteryOptimizations(packageName)
}
