package com.bgm.irena

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.Proxy

@RunWith(AndroidJUnit4::class)
class DirectNetworkProbeTest {
    @Test fun apiLoginAndImageWorkWithoutProxy() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("runDirectNetworkProbe") == "true")
        val client = createBangumiNetworkClient().newBuilder().proxy(Proxy.NO_PROXY).build()
        try {
            for (url in listOf(
                "https://next.bgm.tv/p1/calendar",
                "https://bgm.tv/login",
                "https://lain.bgm.tv/img/smiles/tv/45.gif",
            )) {
                client.newCall(Request.Builder().url(url).build()).execute().use { response ->
                    assertEquals("直连失败：$url", 200, response.code)
                    assertTrue("空响应：$url", response.body!!.bytes().isNotEmpty())
                }
            }
        } finally {
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }
}
