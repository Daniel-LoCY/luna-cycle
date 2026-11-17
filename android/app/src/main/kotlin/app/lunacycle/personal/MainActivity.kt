package app.lunacycle.personal

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "app.lunacycle/update_installer"
        private const val APPLICATION_ID = "app.lunacycle.personal"
    }

    private var hideSwitcherPreview = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getDeviceInfo" -> result.success(deviceInfo())
                        "inspectApk" -> {
                            val path = call.argument<String>("path")
                                ?: throw IllegalArgumentException("APK 路徑缺失")
                            result.success(inspectApk(path))
                        }
                        "requestInstallPermission" -> result.success(requestInstallPermission())
                        "setSwitcherPrivacyEnabled" -> {
                            hideSwitcherPreview = call.argument<Boolean>("enabled") ?: false
                            window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            result.success(null)
                        }
                        "installApk" -> {
                            val path = call.argument<String>("path")
                                ?: throw IllegalArgumentException("APK 路徑缺失")
                            installApk(path)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("UPDATE_INSTALLER_ERROR", error.message, null)
                }
            }
    }

    override fun onPause() {
        if (hideSwitcherPreview) {
            window.setFlags(
                android.view.WindowManager.LayoutParams.FLAG_SECURE,
                android.view.WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
    }

    private fun deviceInfo(): Map<String, Any> {
        val packageInfo = packageManager.getPackageInfoCompat(packageName)
        val signatures = signatures(packageInfo)
        return mapOf(
            "applicationId" to packageName,
            "versionName" to (packageInfo.versionName ?: ""),
            "versionCode" to packageInfo.longVersionCodeCompat(),
            "androidApiLevel" to Build.VERSION.SDK_INT,
            "signingCertificateSha256" to signatures.firstOrNull().orEmpty(),
        )
    }

    private fun inspectApk(path: String): Map<String, Any> {
        val apk = checkedUpdateApk(path)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        val packageInfo = packageManager.getPackageArchiveInfo(apk.absolutePath, flags)
            ?: throw IllegalArgumentException("APK 無法讀取")
        val appInfo = packageInfo.applicationInfo
            ?: throw IllegalArgumentException("APK 缺少 Android 應用程式資訊")
        return mapOf(
            "applicationId" to packageInfo.packageName,
            "versionName" to (packageInfo.versionName ?: ""),
            "versionCode" to packageInfo.longVersionCodeCompat(),
            "minAndroidApi" to appInfo.minSdkVersion,
            "signingCertificateSha256" to signatures(packageInfo).firstOrNull().orEmpty(),
        )
    }

    private fun signatures(packageInfo: PackageInfo): List<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures
        }
        return signatures.orEmpty().map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }
    }

    private fun requestInstallPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()) {
            return true
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
        return false
    }

    private fun installApk(path: String) {
        if (!requestInstallPermission()) {
            throw SecurityException("請先允許 Luna Cycle 安裝本機更新，返回 App 後再點選安裝。")
        }
        val apk = checkedUpdateApk(path)
        val params = android.content.pm.PackageInstaller.SessionParams(
            android.content.pm.PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
            setAppPackageName(APPLICATION_ID)
        }
        val installer = packageManager.packageInstaller
        val sessionId = installer.createSession(params)
        try {
            installer.openSession(sessionId).use { session ->
                FileInputStream(apk).use { input ->
                    session.openWrite("luna-cycle.apk", 0, apk.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                val callback = Intent(this, InstallStatusReceiver::class.java)
                    .setAction("app.lunacycle.INSTALL_STATUS")
                val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_MUTABLE
                    } else {
                        0
                    }
                val statusReceiver = PendingIntent.getBroadcast(
                    this,
                    sessionId,
                    callback,
                    pendingFlags,
                )
                session.commit(statusReceiver.intentSender)
            }
        } catch (error: Exception) {
            installer.abandonSession(sessionId)
            throw error
        }
    }

    private fun checkedUpdateApk(path: String): File {
        val updateDirectory = File(cacheDir, "updates").canonicalFile
        val apk = File(path).canonicalFile
        if (!apk.path.startsWith(updateDirectory.path + File.separator) ||
            !apk.isFile || !apk.canRead() || !apk.name.endsWith(".apk", ignoreCase = true)
        ) {
            throw SecurityException("更新檔案位置或格式不正確")
        }
        return apk
    }

    private fun PackageInfo.longVersionCodeCompat(): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            longVersionCode
        } else {
            @Suppress("DEPRECATION")
            versionCode.toLong()
        }
    }

    @Suppress("DEPRECATION")
    private fun PackageManager.getPackageInfoCompat(packageName: String): PackageInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(
                    (PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES).toLong(),
                ),
            )
        } else {
            getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES,
            )
        }
    }
}
