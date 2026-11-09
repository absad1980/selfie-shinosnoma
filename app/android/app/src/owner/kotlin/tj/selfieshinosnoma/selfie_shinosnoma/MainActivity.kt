package tj.selfieshinosnoma.selfie_shinosnoma

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Owner app: sends activation codes to customers by SMS (from the owner's SIM). */
class MainActivity : FlutterActivity() {
    private var pending: (() -> Unit)? = null
    private var pendingFail: (() -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tj.selfieshinosnoma/sms").setMethodCallHandler { call, result ->
            if (call.method != "send") return@setMethodCallHandler result.notImplemented()
            val to = call.argument<String>("to") ?: return@setMethodCallHandler result.success("bad")
            val text = call.argument<String>("text") ?: return@setMethodCallHandler result.success("bad")
            val send = {
                try {
                    @Suppress("DEPRECATION")
                    val sms = if (Build.VERSION.SDK_INT >= 31) getSystemService(SmsManager::class.java) else SmsManager.getDefault()
                    val parts = sms.divideMessage(text)
                    if (parts.size > 1) sms.sendMultipartTextMessage(to, null, parts, null, null) else sms.sendTextMessage(to, null, text, null, null)
                    result.success("sent")
                } catch (e: Exception) {
                    result.success("failed")
                }
            }
            if (checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
                send()
            } else {
                pending = send
                pendingFail = { result.success("denied") }
                requestPermissions(arrayOf(Manifest.permission.SEND_SMS), 77)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 77) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) pending?.invoke() else pendingFail?.invoke()
        pending = null
        pendingFail = null
    }
}
