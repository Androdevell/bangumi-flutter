package com.bgm.irena

import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.InetAddress
import java.net.Proxy
import java.net.UnknownHostException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * 为本站域名使用限时加密解析；解析服务不可达时使用备用地址，避免受污染的系统解析。
 * 地址只决定连接路由，HTTPS 请求域名、SNI 和证书校验保持不变。
 *
 * @param delegate 非本站域名的系统解析器
 * @param secureLookup 可注入的加密解析函数，便于离线回归测试
 * @param clock 单调时钟，避免设备校时影响缓存寿命
 */
internal class BangumiDns(
    private val delegate: Dns = Dns.SYSTEM,
    private val secureLookup: (String) -> DnsAnswer? = SecureBangumiDns()::lookup,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
) : Dns {
    private data class Cached(val addresses: List<InetAddress>, val expiresAt: Long)
    private val cache = ConcurrentHashMap<String, Cached>()
    private val locks = fallbackAddresses.keys.associateWith { Any() }

    override fun lookup(hostname: String): List<InetAddress> {
        val host = hostname.trim().lowercase().removeSuffix(".")
        val fallback = fallbackAddresses[host] ?: return delegate.lookup(hostname)
        synchronized(locks.getValue(host)) {
            cache[host]?.takeIf { it.expiresAt > clock() }?.let { return it.addresses }
            val answer = runCatching { secureLookup(host) }.getOrNull()
            val resolved = answer?.addresses.orEmpty().mapNotNull { literalAddress(host, it) }
            val addresses = resolved.ifEmpty { fallback.mapNotNull { literalAddress(host, it) } }
            if (addresses.isEmpty()) throw UnknownHostException("Unable to resolve $host")
            val ttl = if (resolved.isEmpty()) 30 else answer!!.ttlSeconds.coerceIn(1, 300)
            return addresses.distinctBy { it.hostAddress }.also {
                cache[host] = Cached(it, clock() + ttl * 1000L)
            }
        }
    }

    companion object {
        // 仅为 DoH 不可用时的应急路由；可用的加密解析结果优先，不永久绑定 CDN。
        private val cdnFallback = listOf("104.26.8.23", "104.26.9.23", "172.67.73.67")
        private val fallbackAddresses = mapOf(
            "bgm.tv" to cdnFallback,
            "api.bgm.tv" to cdnFallback,
            "next.bgm.tv" to cdnFallback,
            "lain.bgm.tv" to cdnFallback,
            "bangumi.tv" to listOf("178.79.181.137"),
            "chii.in" to listOf("104.21.93.3", "172.67.201.187"),
        )

        internal fun literalAddress(host: String, value: String): InetAddress? {
            val octets = value.split('.').map { it.toIntOrNull() }
            if (octets.size != 4 || octets.any { it == null || it !in 0..255 }) return null
            val first = octets[0]!!
            val second = octets[1]!!
            if (first == 0 || first == 10 || first == 127 || first >= 224 ||
                (first == 169 && second == 254) || (first == 172 && second in 16..31) ||
                (first == 192 && second == 168) || (first == 100 && second in 64..127)) return null
            return InetAddress.getByAddress(host, octets.map { it!!.toByte() }.toByteArray())
        }
    }
}

internal data class DnsAnswer(val addresses: List<String>, val ttlSeconds: Int)

/**
 * 独立 HTTPS 解析客户端，使用解析器引导地址，不递归调用业务 DNS，也不依赖本地代理。
 */
private class SecureBangumiDns {
    private val endpoints = listOf(
        "https://dns.google/resolve" to listOf("8.8.8.8", "8.8.4.4"),
        "https://cloudflare-dns.com/dns-query" to listOf("1.1.1.1", "1.0.0.1"),
    )
    private val client = OkHttpClient.Builder()
        .proxy(Proxy.NO_PROXY)
        .dns(object : Dns {
            override fun lookup(hostname: String): List<InetAddress> {
                val ips = when (hostname) {
                    "dns.google" -> endpoints[0].second
                    "cloudflare-dns.com" -> endpoints[1].second
                    else -> throw UnknownHostException("Unexpected DNS resolver")
                }
                return ips.mapNotNull { BangumiDns.literalAddress(hostname, it) }
            }
        })
        .connectTimeout(1, TimeUnit.SECONDS)
        .readTimeout(2, TimeUnit.SECONDS)
        .callTimeout(2, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .build()

    fun lookup(host: String): DnsAnswer? {
        for ((endpoint, _) in endpoints) {
            val answer = runCatching {
                val request = Request.Builder().url("$endpoint?name=$host&type=A")
                    .header("Accept", "application/dns-json").build()
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@use null
                    val body = response.body ?: return@use null
                    val source = body.source()
                    if (source.request(8193)) return@use null
                    val bytes = source.readByteArray()
                    parseDnsAnswer(host, bytes.toString(Charsets.UTF_8))
                }
            }.getOrNull()
            if (answer != null && answer.addresses.isNotEmpty()) return answer
        }
        return null
    }
}

/**
 * 只接受成功且未截断的 A 记录；禁止将返回值再次交给系统 DNS 或作为私网连接地址。
 *
 * @param host 被查询的原始域名
 * @param text 加密解析服务的 JSON 响应
 */
internal fun parseDnsAnswer(host: String, text: String): DnsAnswer? {
    val json = JSONObject(text)
    if (json.optInt("Status", -1) != 0 || json.optBoolean("TC", false)) return null
    val question = json.optJSONArray("Question")?.optJSONObject(0) ?: return null
    if (question.optString("name").removeSuffix(".").lowercase() != host ||
        question.optInt("type") != 1) return null
    val records = json.optJSONArray("Answer") ?: return null
    val addresses = mutableListOf<String>()
    var ttl = 300
    for (index in 0 until records.length()) {
        val record = records.optJSONObject(index) ?: continue
        if (record.optInt("type") != 1) continue
        val value = record.optString("data")
        if (BangumiDns.literalAddress(host, value) == null) continue
        addresses += value
        ttl = minOf(ttl, record.optInt("TTL", 30).coerceIn(1, 300))
    }
    return if (addresses.isEmpty()) null else DnsAnswer(addresses.distinct(), ttl)
}
