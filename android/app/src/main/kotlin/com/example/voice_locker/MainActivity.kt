package com.example.voice_locker // Make sure this matches your package name!

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MyAdmin : DeviceAdminReceiver()

// This new receiver listens for the background broadcast and locks the phone
class LockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "com.voice_locker.LOCK_SCREEN") {
            val policyManager = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminReceiver = ComponentName(context, MyAdmin::class.java)
            if (policyManager.isAdminActive(adminReceiver)) {
                policyManager.lockNow()
            }
        }
    }
}

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // This is strictly to ask for the Admin permission when you open the UI
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.voice_locker/admin").setMethodCallHandler { call, result ->
            if (call.method == "requestAdmin") {
                val policyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val adminReceiver = ComponentName(this, MyAdmin::class.java)
                if (!policyManager.isAdminActive(adminReceiver)) {
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                    intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminReceiver)
                    intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Required to lock the screen.")
                    startActivity(intent)
                }
                result.success(true)
            }
        }
    }
}