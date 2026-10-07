package com.hyouka.mail

import android.content.ContentValues
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.hyouka.mail/diagnostics"
    }

    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    @Volatile private var logUri: Uri? = null
    @Volatile private var legacyLogFile: File? = null
    @Volatile private var logDisplayPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> ioExecutor.execute {
                        try {
                            val path = createLogFile()
                            val response = HashMap<String, Any?>(collectDiagnostics())
                            response["logPath"] = path
                            completeResult(result, response)
                        } catch (error: Exception) {
                            failResult(result, "LOGGER_INIT_FAILED", error)
                        }
                    }

                    "writeLog" -> {
                        val line = call.argument<String>("line").orEmpty()
                        ioExecutor.execute {
                            try {
                                if (logUri == null && legacyLogFile == null) {
                                    createLogFile()
                                }
                                appendLog(line)
                                completeResult(result, logDisplayPath)
                            } catch (error: Exception) {
                                failResult(result, "LOGGER_WRITE_FAILED", error)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun createLogFile(): String {
        logUri = null
        legacyLogFile = null

        val timestamp = SimpleDateFormat(
            "yyyyMMdd_HHmmss_SSS",
            Locale.US,
        ).format(Date())
        val displayName = "Mail_GoogleSignIn_" + timestamp + ".log"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS,
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values,
            ) ?: error("MediaStore.Downloads insert returned null")

            logUri = uri
            logDisplayPath = "Download/" + displayName
            writeToUri(uri, "# Mail Google Sign-In diagnostic log\n")

            contentResolver.update(
                uri,
                ContentValues().apply {
                    put(MediaStore.Downloads.IS_PENDING, 0)
                },
                null,
                null,
            )
            return logDisplayPath!!
        }

        val directory = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: error("App-specific Downloads directory unavailable")
        val file = File(directory, displayName)
        legacyLogFile = file
        logDisplayPath = file.absolutePath
        file.writeText("# Mail Google Sign-In diagnostic log\n")
        return logDisplayPath!!
    }

    private fun appendLog(line: String) {
        val uri = logUri
        if (uri != null) {
            writeToUri(uri, line)
            return
        }
        val file = legacyLogFile
        if (file != null) {
            file.appendText(line)
            return
        }
        error("Diagnostic log file is not initialized")
    }

    private fun writeToUri(uri: Uri, text: String) {
        contentResolver.openOutputStream(uri, "wa")?.use { stream ->
            stream.write(text.toByteArray(Charsets.UTF_8))
            stream.flush()
        } ?: error("Unable to open diagnostic log for append")
    }

    private fun collectDiagnostics(): Map<String, Any?> {
        val packageInfo = packageInfo()
        val appInfo = applicationInfo
        val certificates = signingCertificates(packageInfo)
        val sha1 = certificates.firstOrNull()?.let { digest(it.toByteArray(), "SHA-1") }
        val sha256 = certificates.firstOrNull()?.let { digest(it.toByteArray(), "SHA-256") }
        val historySha256 = certificates.drop(1).map {
            digest(it.toByteArray(), "SHA-256")
        }
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runCatching {
                packageManager.getInstallSourceInfo(packageName).installingPackageName
            }.getOrNull()
        } else {
            null
        }

        return mapOf(
            "package_name" to packageName,
            "version_name" to (packageInfo.versionName ?: "unknown"),
            "version_code" to packageVersionCode(packageInfo),
            "debuggable" to ((appInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
            "target_sdk" to appInfo.targetSdkVersion,
            "android_sdk" to Build.VERSION.SDK_INT,
            "android_release" to Build.VERSION.RELEASE,
            "device_manufacturer" to Build.MANUFACTURER,
            "device_model" to Build.MODEL,
            "installer_package" to installer,
            "google_play_services_version" to packageVersion("com.google.android.gms"),
            "signing_sha1" to sha1,
            "signing_sha256" to sha256,
            "signing_history_sha256" to historySha256,
        )
    }

    private fun packageInfo(): PackageInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(
                    PackageManager.GET_SIGNING_CERTIFICATES.toLong(),
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun packageVersion(packageName: String): String? {
        return runCatching {
            val info = packageManager.getPackageInfo(packageName, 0)
            packageVersionCode(info).toString()
        }.getOrNull()
    }

    @Suppress("DEPRECATION")
    private fun packageVersionCode(info: PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
    }

    @Suppress("DEPRECATION")
    private fun signingCertificates(info: PackageInfo): List<android.content.pm.Signature> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptyList()
            return if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners.toList()
            } else {
                signingInfo.signingCertificateHistory.toList()
            }
        }
        return info.signatures?.toList().orEmpty()
    }

    private fun digest(bytes: ByteArray, algorithm: String): String {
        return MessageDigest.getInstance(algorithm)
            .digest(bytes)
            .joinToString(":") {
                String.format(Locale.US, "%02X", it.toInt() and 0xFF)
            }
    }

    private fun completeResult(result: MethodChannel.Result, value: Any?) {
        runOnUiThread { result.success(value) }
    }

    private fun failResult(result: MethodChannel.Result, code: String, error: Exception) {
        runOnUiThread {
            result.error(
                code,
                error.message ?: error.javaClass.simpleName,
                error.stackTraceToString(),
            )
        }
    }

    override fun onDestroy() {
        ioExecutor.shutdownNow()
        super.onDestroy()
    }
}
