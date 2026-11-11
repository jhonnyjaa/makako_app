package com.makako.makako

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "makako/whatsapp_stickers"
    private val addPackRequest = 4242
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWhatsAppInstalled" -> result.success(
                    isInstalled("com.whatsapp") || isInstalled("com.whatsapp.w4b")
                )
                "addStickerPack" -> {
                    val id = call.argument<String>("identifier")
                    val name = call.argument<String>("name")
                    if (id == null || name == null) {
                        result.error("ARGS", "identifier and name are required", null)
                        return@setMethodCallHandler
                    }
                    addStickerPack(id, name, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun addStickerPack(identifier: String, name: String, result: MethodChannel.Result) {
        val intent = Intent("com.whatsapp.intent.action.ENABLE_STICKER_PACK").apply {
            putExtra("sticker_pack_id", identifier)
            putExtra("sticker_pack_authority", "$packageName.stickercontentprovider")
            putExtra("sticker_pack_name", name)
        }
        // Prefer consumer WhatsApp, fall back to Business.
        when {
            isInstalled("com.whatsapp") -> intent.setPackage("com.whatsapp")
            isInstalled("com.whatsapp.w4b") -> intent.setPackage("com.whatsapp.w4b")
            else -> {
                result.error("NOT_INSTALLED", "WhatsApp no está instalado", null)
                return
            }
        }
        try {
            pendingResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(intent, addPackRequest)
        } catch (e: ActivityNotFoundException) {
            pendingResult = null
            result.error("NOT_FOUND", "WhatsApp no pudo abrir el pack", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != addPackRequest) return
        val r = pendingResult ?: return
        pendingResult = null
        when (resultCode) {
            Activity.RESULT_OK -> r.success("added")
            else -> {
                val error = data?.getStringExtra("validation_error")
                if (error != null) r.error("VALIDATION", error, null) else r.success("cancelled")
            }
        }
    }
}
