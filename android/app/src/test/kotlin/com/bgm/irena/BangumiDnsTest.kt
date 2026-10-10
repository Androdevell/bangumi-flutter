package com.bgm.irena

import okhttp3.Dns
import org.junit.Assert.*
import org.junit.Test
import java.net.InetAddress
import java.net.UnknownHostException

class BangumiDnsTest {
    private fun dnsResolver(lookup: (String) -> List<InetAddress>): Dns = object : Dns {
        override fun lookup(hostname: String) = lookup.invoke(hostname)
    }
    private val poisonedSystem = dnsResolver { error("本站解析不应依赖受污染的系统 DNS") }

    @Test fun secureAnswersOverrideFallbackAndKeepHostname() {
        val dns = BangumiDns(poisonedSystem, { DnsAnswer(listOf("8.8.4.4"), 60) })
        val address = dns.lookup("NEXT.BGM.TV.").single()
        assertEquals("8.8.4.4", address.hostAddress)
        assertEquals("next.bgm.tv", address.hostName)
    }

    @Test fun unavailableResolversStillReturnMultipleDirectRoutes() {
        val dns = BangumiDns(poisonedSystem, { throw UnknownHostException("offline DoH") })
        for (host in listOf("next.bgm.tv", "bgm.tv", "api.bgm.tv", "lain.bgm.tv", "bangumi.tv", "chii.in")) {
            val addresses = dns.lookup(host)
            assertTrue(addresses.isNotEmpty())
            assertTrue(addresses.all { it.hostName == host })
        }
        assertEquals(3, dns.lookup("next.bgm.tv").size)
    }

    @Test fun cacheRespectsTtlAndRefreshesAfterExpiration() {
        var now = 0L
        var calls = 0
        val dns = BangumiDns(poisonedSystem, { calls++; DnsAnswer(listOf("8.8.8.8"), 2) }, { now })
        dns.lookup("next.bgm.tv")
        now = 1999
        dns.lookup("next.bgm.tv")
        assertEquals(1, calls)
        now = 2000
        dns.lookup("next.bgm.tv")
        assertEquals(2, calls)
    }

    @Test fun fallbackIsRetriedRatherThanPinnedForever() {
        var now = 0L
        var available = false
        val dns = BangumiDns(poisonedSystem, { if (available) DnsAnswer(listOf("8.8.8.8"), 60) else null }, { now })
        assertEquals(3, dns.lookup("next.bgm.tv").size)
        available = true
        now = 30000
        assertEquals("8.8.8.8", dns.lookup("next.bgm.tv").single().hostAddress)
    }

    @Test fun unrelatedHostsUseSystemDnsWithoutSecureQuery() {
        var calls = 0
        val expected = listOf(InetAddress.getByAddress(byteArrayOf(1, 1, 1, 1)))
        val dns = BangumiDns(dnsResolver { calls++; expected }, { error("不查询第三方域名") })
        assertEquals(expected, dns.lookup("example.com"))
        assertEquals(expected, dns.lookup("evil.bgm.tv"))
        assertEquals(2, calls)
    }

    @Test fun parserRejectsPrivateAddressesAndWrongQuestions() {
        val response = """{"Status":0,"Question":[{"name":"next.bgm.tv.","type":1}],"Answer":[{"type":1,"TTL":10,"data":"127.0.0.1"},{"type":1,"TTL":20,"data":"8.8.8.8"}]}"""
        val answer = parseDnsAnswer("next.bgm.tv", response)!!
        assertEquals(listOf("8.8.8.8"), answer.addresses)
        assertEquals(20, answer.ttlSeconds)
        assertNull(parseDnsAnswer("bgm.tv", response))
        assertNull(parseDnsAnswer("next.bgm.tv", response.replace("\"Status\":0", "\"Status\":3")))
        for (value in listOf("localhost", "10.0.0.1", "192.168.1.1", "100.64.1.1", "169.254.1.1", "256.1.1.1")) {
            assertNull(BangumiDns.literalAddress("next.bgm.tv", value))
        }
    }
}
