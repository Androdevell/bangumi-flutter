package com.bgm.irena

import android.app.Activity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Dns
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.conscrypt.Conscrypt
import java.io.ByteArrayOutputStream
import java.io.FilterOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketAddress
import java.net.UnknownHostException
import java.nio.ByteBuffer
import java.security.KeyStore
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.net.SocketFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

class BangumiNetworkBridge(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {
    private val client = createClient()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "request") {
            result.notImplemented()
            return
        }

        val arguments = call.arguments as? Map<*, *>
        val method = arguments?.get("method") as? String
        val url = arguments?.get("url") as? String
        if (method.isNullOrBlank() || url.isNullOrBlank()) {
            result.error("invalid_request", "HTTP method or URL is missing", null)
            return
        }

        val requestBuilder = Request.Builder().url(url)
        (arguments["headers"] as? Map<*, *>)?.forEach { (name, value) ->
            if (name != null && value != null) {
                requestBuilder.header(name.toString(), value.toString())
            }
        }

        val bodyBytes = arguments["body"] as? ByteArray ?: ByteArray(0)
        val requestBody = if (method.equals("GET", ignoreCase = true) ||
            method.equals("HEAD", ignoreCase = true)
        ) {
            null
        } else {
            bodyBytes.toRequestBody(
                requestBuilder.build().header("Content-Type")?.toMediaTypeOrNull(),
            )
        }
        val request = requestBuilder.method(method, requestBody).build()

        val followRedirects = arguments["followRedirects"] as? Boolean ?: true
        val requestClient = if (followRedirects) {
            client
        } else {
            client.newBuilder()
                .followRedirects(false)
                .followSslRedirects(false)
                .build()
        }

        requestClient.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                activity.runOnUiThread {
                    result.error("network_error", error.message ?: "Network request failed", null)
                }
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val responseBody = it.body?.bytes() ?: ByteArray(0)
                    val headers = it.headers.names().associateWith { name ->
                        it.headers.values(name).joinToString(", ")
                    }
                    activity.runOnUiThread {
                        result.success(
                            mapOf(
                                "statusCode" to it.code,
                                "reasonPhrase" to it.message,
                                "isRedirect" to it.isRedirect,
                                "headers" to headers,
                                "body" to responseBody,
                            ),
                        )
                    }
                }
            }
        })
    }

    private fun createClient(): OkHttpClient {
        val hosts = mapOf(
            "bangumi.tv" to listOf("178.79.181.137"),
            "bgm.tv" to CLOUDFLARE_IPS,
            "api.bgm.tv" to CLOUDFLARE_IPS,
            "next.bgm.tv" to CLOUDFLARE_IPS,
            "lain.bgm.tv" to CLOUDFLARE_IPS,
        )
        val fragmentationPolicy = DomainTlsFragmentationPolicy(hosts.keys)
        return OkHttpClient.Builder()
            .dns(AntiSniDns(hosts))
            .socketFactory(AntiSniSocketFactory(fragmentationPolicy))
            .sslSocketFactory(antiSniTlsEngine.socketFactory, antiSniTlsEngine.trustManager)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build()
    }

    companion object {
        const val CHANNEL_NAME = "com.xiaoyv.bangumi/network"

        private val CLOUDFLARE_IPS = listOf(
            "104.26.8.23",
            "104.26.9.23",
            "172.67.73.67",
        )
    }
}

private class AntiSniDns(
    initialHosts: Map<String, List<String>>,
    private val delegate: Dns = Dns.SYSTEM,
) : Dns {
    private val hostsMap = ConcurrentHashMap(initialHosts)

    override fun lookup(hostname: String): List<InetAddress> {
        val addresses = hostsMap[hostname]?.mapNotNull { ip ->
            runCatching {
                InetAddress.getByAddress(hostname, InetAddress.getByName(ip).address)
            }.getOrNull()
        }.orEmpty()
        if (addresses.isNotEmpty()) return addresses

        return try {
            delegate.lookup(hostname)
        } catch (error: Exception) {
            throw UnknownHostException(
                "Unable to resolve host: $hostname. Cause: ${error.message}",
            )
        }
    }
}

private fun interface TlsFragmentationPolicy {
    fun shouldFragment(hostname: String?): Boolean
}

private class DomainTlsFragmentationPolicy(domains: Collection<String>) : TlsFragmentationPolicy {
    private val normalizedDomains = domains
        .map(String::normalizeHostname)
        .filter(String::isNotEmpty)
        .toSet()

    override fun shouldFragment(hostname: String?): Boolean {
        val normalizedHost = hostname?.normalizeHostname().orEmpty()
        return normalizedDomains.any { domain ->
            normalizedHost == domain || normalizedHost.endsWith(".$domain")
        }
    }
}

private fun String.normalizeHostname(): String = trim().lowercase().removeSuffix(".")

private class AntiSniSocketFactory(
    private val fragmentationPolicy: TlsFragmentationPolicy,
) : SocketFactory() {
    private val defaultFactory = getDefault()

    override fun createSocket(): Socket =
        AntiSniSocket(defaultFactory.createSocket(), fragmentationPolicy)

    override fun createSocket(host: String, port: Int): Socket =
        AntiSniSocket(defaultFactory.createSocket(host, port), fragmentationPolicy, host)

    override fun createSocket(
        host: String,
        port: Int,
        localHost: InetAddress,
        localPort: Int,
    ): Socket = AntiSniSocket(
        defaultFactory.createSocket(host, port, localHost, localPort),
        fragmentationPolicy,
        host,
    )

    override fun createSocket(host: InetAddress, port: Int): Socket =
        AntiSniSocket(defaultFactory.createSocket(host, port), fragmentationPolicy, host.hostName)

    override fun createSocket(
        address: InetAddress,
        port: Int,
        localAddress: InetAddress,
        localPort: Int,
    ): Socket = AntiSniSocket(
        defaultFactory.createSocket(address, port, localAddress, localPort),
        fragmentationPolicy,
        address.hostName,
    )
}

private class AntiSniSocket(
    private val delegate: Socket,
    private val fragmentationPolicy: TlsFragmentationPolicy,
    initialHost: String? = null,
) : Socket() {
    @Volatile
    private var fragmentationEnabled = fragmentationPolicy.shouldFragment(initialHost)

    private val fragmentingOutputStream by lazy {
        FragmentingOutputStream(delegate.getOutputStream())
    }

    override fun getOutputStream(): OutputStream = fragmentingOutputStream
    override fun getInputStream(): InputStream = delegate.getInputStream()
    override fun bind(bindpoint: SocketAddress?) = delegate.bind(bindpoint)

    override fun connect(endpoint: SocketAddress?) {
        captureHost(endpoint)
        delegate.connect(endpoint)
    }

    override fun connect(endpoint: SocketAddress?, timeout: Int) {
        captureHost(endpoint)
        delegate.connect(endpoint, timeout)
    }

    override fun close() = delegate.close()
    override fun isConnected() = delegate.isConnected
    override fun isClosed() = delegate.isClosed
    override fun isBound() = delegate.isBound
    override fun isInputShutdown() = delegate.isInputShutdown
    override fun isOutputShutdown() = delegate.isOutputShutdown
    override fun shutdownInput() = delegate.shutdownInput()
    override fun shutdownOutput() = delegate.shutdownOutput()
    override fun getInetAddress(): InetAddress? = delegate.inetAddress
    override fun getLocalAddress(): InetAddress? = delegate.localAddress
    override fun getPort() = delegate.port
    override fun getLocalPort() = delegate.localPort
    override fun getRemoteSocketAddress(): SocketAddress? = delegate.remoteSocketAddress
    override fun getLocalSocketAddress(): SocketAddress? = delegate.localSocketAddress
    override fun setTcpNoDelay(on: Boolean) { delegate.tcpNoDelay = on }
    override fun getTcpNoDelay() = delegate.tcpNoDelay
    override fun setSoLinger(on: Boolean, linger: Int) = delegate.setSoLinger(on, linger)
    override fun getSoLinger() = delegate.soLinger
    override fun sendUrgentData(data: Int) = delegate.sendUrgentData(data)
    override fun setOOBInline(on: Boolean) { delegate.oobInline = on }
    override fun getOOBInline() = delegate.oobInline
    override fun setSoTimeout(timeout: Int) { delegate.soTimeout = timeout }
    override fun getSoTimeout() = delegate.soTimeout
    override fun setSendBufferSize(size: Int) { delegate.sendBufferSize = size }
    override fun getSendBufferSize() = delegate.sendBufferSize
    override fun setReceiveBufferSize(size: Int) { delegate.receiveBufferSize = size }
    override fun getReceiveBufferSize() = delegate.receiveBufferSize
    override fun setKeepAlive(on: Boolean) { delegate.keepAlive = on }
    override fun getKeepAlive() = delegate.keepAlive
    override fun setTrafficClass(tc: Int) { delegate.trafficClass = tc }
    override fun getTrafficClass() = delegate.trafficClass
    override fun setReuseAddress(on: Boolean) { delegate.reuseAddress = on }
    override fun getReuseAddress() = delegate.reuseAddress

    override fun setPerformancePreferences(connectionTime: Int, latency: Int, bandwidth: Int) {
        delegate.setPerformancePreferences(connectionTime, latency, bandwidth)
    }

    override fun toString() = delegate.toString()

    private fun captureHost(endpoint: SocketAddress?) {
        val host = (endpoint as? InetSocketAddress)?.hostString
        if (!host.isNullOrBlank()) fragmentationEnabled = fragmentationPolicy.shouldFragment(host)
    }

    private inner class FragmentingOutputStream(originalStream: OutputStream) :
        FilterOutputStream(originalStream) {
        private val pending = ByteArrayOutputStream()
        private var firstRecordHandled = false

        override fun write(value: Int) = write(byteArrayOf(value.toByte()), 0, 1)

        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            if (length <= 0) return
            if (firstRecordHandled || !fragmentationEnabled) {
                firstRecordHandled = true
                out.write(bytes, offset, length)
                return
            }

            pending.write(bytes, offset, length)
            val buffered = pending.toByteArray()
            val recordLength = TlsFragmentation.firstRecordLengthOrNull(buffered) ?: return
            if (buffered.size < recordLength) return

            firstRecordHandled = true
            pending.reset()
            val firstRecord = buffered.copyOfRange(0, recordLength)
            if (!TlsFragmentation.sendClientHelloFragments(out, firstRecord)) out.write(firstRecord)
            if (buffered.size > recordLength) out.write(buffered, recordLength, buffered.size - recordLength)
            out.flush()
        }

        override fun flush() {
            if (firstRecordHandled) out.flush()
        }
    }
}

private val antiSniTlsEngine by lazy {
    val trustManagerFactory = TrustManagerFactory.getInstance(
        TrustManagerFactory.getDefaultAlgorithm(),
    ).apply { init(null as KeyStore?) }
    val trustManager = trustManagerFactory.trustManagers
        .filterIsInstance<X509TrustManager>()
        .singleOrNull()
        ?: error("Unable to obtain the default X509TrustManager")
    val socketFactory = SSLContext.getInstance("TLS", Conscrypt.newProvider())
        .apply { init(null, arrayOf(trustManager), null) }
        .socketFactory
        .also { Conscrypt.setUseEngineSocket(it, true) }

    AntiSniTlsEngine(socketFactory, trustManager)
}

private data class AntiSniTlsEngine(
    val socketFactory: SSLSocketFactory,
    val trustManager: X509TrustManager,
)

private object TlsFragmentation {
    private const val TLS_HANDSHAKE = 0x16
    private const val CLIENT_HELLO = 0x01
    private const val TLS_HEADER_SIZE = 5
    private const val TLS_RECORD_COUNT = 4

    fun firstRecordLengthOrNull(data: ByteArray): Int? {
        if (data.size < TLS_HEADER_SIZE) return null
        if (data[0].toInt() and 0xFF != TLS_HANDSHAKE) return data.size
        return readUnsignedShort(data[3], data[4]) + TLS_HEADER_SIZE
    }

    fun sendClientHelloFragments(output: OutputStream, record: ByteArray): Boolean {
        if (!looksLikeTlsHandshake(record)) return false
        val mutableRecord = record.copyOf()
        val sni = parseSni(mutableRecord) ?: return false
        mutableRecord[2] = 0x04

        val lastDot = findLastDot(mutableRecord, sni.position, sni.length)
        val header = mutableRecord.copyOfRange(0, 3)
        val payloadBeforeDot = mutableRecord.copyOfRange(TLS_HEADER_SIZE, lastDot)
        val payloadAfterDot = mutableRecord.copyOfRange(lastDot, mutableRecord.size)
        val records = buildList {
            addAll(splitIntoTlsRecords(header, payloadBeforeDot, TLS_RECORD_COUNT / 2))
            addAll(splitIntoTlsRecords(header, payloadAfterDot, TLS_RECORD_COUNT - size))
        }
        if (records.isEmpty()) return false

        val merged = ByteArrayOutputStream(record.size + records.size * TLS_HEADER_SIZE)
        records.forEach(merged::write)
        output.write(merged.toByteArray())
        return true
    }

    private fun looksLikeTlsHandshake(record: ByteArray): Boolean =
        record.size >= TLS_HEADER_SIZE + 4 &&
            record[0].toInt() and 0xFF == TLS_HANDSHAKE &&
            record[1].toInt() and 0xFF == 0x03 &&
            record[TLS_HEADER_SIZE].toInt() and 0xFF == CLIENT_HELLO

    private fun parseSni(record: ByteArray): SniLocation? {
        if (!looksLikeTlsHandshake(record)) return null
        val payloadLimit = readUnsignedShort(record[3], record[4]) + TLS_HEADER_SIZE
        if (payloadLimit > record.size) return null

        var offset = TLS_HEADER_SIZE
        val handshakeLength = readUnsignedMedium(record, offset + 1)
        offset += 4
        if (offset + handshakeLength > payloadLimit) return null
        offset += 34
        if (offset >= payloadLimit) return null
        offset += 1 + (record[offset].toInt() and 0xFF)
        if (offset + 2 > payloadLimit) return null
        offset += 2 + readUnsignedShort(record[offset], record[offset + 1])
        if (offset >= payloadLimit) return null
        offset += 1 + (record[offset].toInt() and 0xFF)
        if (offset + 2 > payloadLimit) return null

        val extensionsLength = readUnsignedShort(record[offset], record[offset + 1])
        offset += 2
        val extensionsEnd = offset + extensionsLength
        if (extensionsEnd > payloadLimit) return null

        while (offset + 4 <= extensionsEnd) {
            val extensionType = readUnsignedShort(record[offset], record[offset + 1])
            val extensionLength = readUnsignedShort(record[offset + 2], record[offset + 3])
            val extensionDataStart = offset + 4
            val extensionDataEnd = extensionDataStart + extensionLength
            if (extensionDataEnd > extensionsEnd) return null
            if (extensionType == 0x0000) {
                if (extensionLength < 5) return null
                val listLength = readUnsignedShort(
                    record[extensionDataStart],
                    record[extensionDataStart + 1],
                )
                if (listLength + 2 > extensionLength) return null
                val nameTypeOffset = extensionDataStart + 2
                if (record[nameTypeOffset].toInt() != 0) return null
                val nameLength = readUnsignedShort(
                    record[nameTypeOffset + 1],
                    record[nameTypeOffset + 2],
                )
                val nameStart = nameTypeOffset + 3
                if (nameStart + nameLength > extensionDataEnd) return null
                return SniLocation(nameStart, nameLength)
            }
            offset = extensionDataEnd
        }
        return null
    }

    private fun findLastDot(record: ByteArray, position: Int, length: Int): Int {
        for (index in position + length - 1 downTo position) {
            if (record[index] == '.'.code.toByte()) return index
        }
        return position + length / 2
    }

    private fun splitIntoTlsRecords(
        header: ByteArray,
        payload: ByteArray,
        count: Int,
    ): List<ByteArray> {
        if (payload.isEmpty() || count <= 0) return emptyList()
        if (count == 1 || payload.size <= count) return listOf(createTlsRecord(header, payload))
        val result = ArrayList<ByteArray>(count)
        val chunkSize = payload.size / count
        var start = 0
        repeat(count) { index ->
            val end = if (index == count - 1) payload.size else start + chunkSize
            result += createTlsRecord(header, payload.copyOfRange(start, end))
            start = end
        }
        return result
    }

    private fun createTlsRecord(header: ByteArray, payload: ByteArray): ByteArray =
        ByteBuffer.allocate(TLS_HEADER_SIZE + payload.size)
            .put(header)
            .putShort(payload.size.toShort())
            .put(payload)
            .array()

    private fun readUnsignedShort(high: Byte, low: Byte): Int =
        ((high.toInt() and 0xFF) shl 8) or (low.toInt() and 0xFF)

    private fun readUnsignedMedium(data: ByteArray, offset: Int): Int =
        ((data[offset].toInt() and 0xFF) shl 16) or
            ((data[offset + 1].toInt() and 0xFF) shl 8) or
            (data[offset + 2].toInt() and 0xFF)

    private data class SniLocation(val position: Int, val length: Int)
}
