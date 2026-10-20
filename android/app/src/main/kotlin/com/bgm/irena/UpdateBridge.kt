package com.bgm.irena

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.Call
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.security.MessageDigest

/**
 * 更新包流式落盘，进度通过通道回传；安装仅开放应用更新目录。
 */
class UpdateBridge(private val activity: MainActivity, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {
    private val client = createBangumiNetworkClient().newBuilder()
        .followRedirects(false).followSslRedirects(false)
        .callTimeout(5, TimeUnit.MINUTES).build()
    private val calls = ConcurrentHashMap<String, Call>()
    private val cancelled = ConcurrentHashMap.newKeySet<String>()
    private val worker = Executors.newSingleThreadExecutor()
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancel" -> {
                val id = call.argument<String>("id") ?: ""
                cancelled.add(id)
                calls.remove(id)?.cancel()
                result.success(null)
            }
            "download" -> {
                val id = call.argument<String>("id") ?: ""
                val name = call.argument<String>("name") ?: ""
                val url = call.argument<String>("url") ?: ""
                val size = call.argument<Number>("size")?.toLong() ?: 0
                if (!Regex("^[0-9]+$").matches(id) ||
                    !Regex("^bangumi-[0-9.]+-arm64-v8a\\.apk$").matches(name) ||
                    size <= 0 || size > 512L * 1024 * 1024) {
                    result.error("invalid_download", "Invalid package", null)
                    return
                }
                cancelled.remove(id)
                worker.execute { download(id, name, url, size, result) }
            }
            "install" -> {
                val path = call.argument<String>("path") ?: ""
                val digest = call.argument<String>("sha256") ?: ""
                worker.execute {
                  try {
                    val file = File(path).canonicalFile
                    require(validPackage(file, digest))
                    activity.runOnUiThread {
                      try {
                    if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}")))
                    } else {
                        val uri = FileProvider.getUriForFile(activity,
                            "${activity.packageName}.updates", file)
                        activity.startActivity(Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                    }
                    result.success(true)
                      } catch (_: Exception) { result.success(false) }
                    }
                  } catch (_: Exception) { activity.runOnUiThread { result.success(false) } }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun validPackage(file: File, expectedDigest: String): Boolean {
        val folder = File(activity.cacheDir, "updates").canonicalFile
        if (file.parentFile != folder || !file.isFile || !file.name.endsWith(".apk") ||
            !Regex("^[a-fA-F0-9]{64}$").matches(expectedDigest)) return false
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val bytes = ByteArray(64 * 1024)
            while (true) { val n = input.read(bytes); if (n < 0) break; digest.update(bytes, 0, n) }
        }
        if (digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) } != expectedDigest.lowercase()) return false
        val flags = PackageManager.GET_SIGNING_CERTIFICATES
        val installed = activity.packageManager.getPackageInfo(activity.packageName, flags)
        val candidate = activity.packageManager.getPackageArchiveInfo(file.path, flags) ?: return false
        fun signers(info: android.content.pm.PackageInfo) = info.signingInfo?.apkContentsSigners
            ?.map { it.toCharsString() }?.toSet().orEmpty()
        val history = candidate.signingInfo?.signingCertificateHistory
            ?.map { it.toCharsString() }?.toSet().orEmpty()
        return UpdatePackagePolicy.accepts(installed.packageName, candidate.packageName,
            installed.longVersionCode, candidate.longVersionCode,
            signers(installed), signers(candidate), history)
    }

    private fun download(id: String, name: String, initial: String, size: Long, result: MethodChannel.Result) {
        var part: File? = null
        try {
            var url = initial
            var completed = false
            for (redirect in 0..5) {
                val uri = Uri.parse(url)
                val allowed = uri.host in setOf("release-assets.githubusercontent.com", "objects.githubusercontent.com") ||
                    (uri.host == "github.com" && uri.path?.startsWith("/Androdevell/bangumi-flutter/releases/download/") == true)
                require(allowed && uri.scheme == "https" && (uri.port == -1 || uri.port == 443) && uri.userInfo == null)
                if (cancelled.contains(id)) throw IOException("Cancelled")
                val request = client.newCall(Request.Builder().url(url).get().build())
                calls[id] = request
                if (cancelled.contains(id)) request.cancel()
                request.execute().use { response ->
                    if (response.code in setOf(301, 302, 303, 307, 308)) {
                        url = response.request.url.resolve(response.header("Location") ?: "")?.toString()
                            ?: throw IOException("Invalid redirect")
                    } else {
                        if (response.code != 200) throw IOException("Download response")
                        val body = response.body ?: throw IOException("Empty package")
                        if (body.contentLength() >= 0 && body.contentLength() != size) throw IOException("Package size")
                        val folder = File(activity.cacheDir, "updates").apply { mkdirs() }
                        val outputFile = File(folder, "$id-$name.part")
                        part = outputFile
                        var received = 0L
                        var lastProgress = 0L
                        body.byteStream().use { input ->
                            outputFile.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    if (cancelled.contains(id)) throw IOException("Cancelled")
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    received += count
                                    if (received > size) throw IOException("Package size")
                                    output.write(buffer, 0, count)
                                    val now = System.currentTimeMillis()
                                    if (now - lastProgress > 150) {
                                        lastProgress = now
                                        val transferred = received
                                        activity.runOnUiThread { channel.invokeMethod("progress",
                                            mapOf("id" to id, "received" to transferred)) }
                                    }
                                }
                            }
                        }
                        if (received != size || cancelled.contains(id)) throw IOException("Incomplete package")
                        completed = true
                    }
                }
                calls.remove(id, request)
                if (completed) break
            }
            if (!completed) throw IOException("Redirect limit")
            val path = part!!.absolutePath
            activity.runOnUiThread { result.success(path) }
        } catch (_: Exception) {
            part?.delete()
            activity.runOnUiThread { result.error("download_failed", "Package download failed", null) }
        } finally { calls.remove(id); cancelled.remove(id) }
    }
    fun close() { calls.values.forEach { it.cancel() }; worker.shutdownNow() }
}
