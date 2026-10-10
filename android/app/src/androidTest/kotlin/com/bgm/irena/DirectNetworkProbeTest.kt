package com.bgm.irena

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.Proxy
import org.json.JSONObject

@RunWith(AndroidJUnit4::class)
class DirectNetworkProbeTest {
    @Test fun tvPreviewCanonicalRedirectAndImageWorkWithoutProxy() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("runDirectPreviewProbe") == "true")
        val client = createBangumiNetworkClient().newBuilder()
            .proxy(Proxy.NO_PROXY).followRedirects(false).followSslRedirects(false).build()
        try {
            val movieUrl = "https://m.douban.com/rexxar/api/v2/movie/36575506/photos?start=0&count=24"
            val tvUrl = "https://m.douban.com/rexxar/api/v2/tv/36575506/photos?start=0&count=24"
            fun request(url: String) = Request.Builder().url(url)
                .header("Referer", "https://m.douban.com/")
                .header("User-Agent", "Mozilla/5.0").build()
            client.newCall(request(movieUrl)).execute().use { response ->
                assertEquals(301, response.code)
                assertEquals(tvUrl, response.request.url.resolve(response.header("Location")!!)!!.toString())
            }
            val imageUrl = client.newCall(request(tvUrl)).execute().use { response ->
                assertEquals(200, response.code)
                val photos = JSONObject(response.body!!.string()).getJSONArray("photos")
                assertTrue(photos.length() > 0)
                photos.getJSONObject(0).getJSONObject("image").getJSONObject("normal").getString("url")
            }
            client.newCall(request(imageUrl)).execute().use { response ->
                assertEquals(200, response.code)
                assertTrue(response.header("Content-Type").orEmpty().startsWith("image/"))
                assertTrue(response.body!!.bytes().isNotEmpty())
            }
        } finally {
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }

    @Test fun publicPreviewApiAndImageWorkWithoutPrivateKeys() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("runDirectPreviewProbe") == "true")
        val client = createBangumiNetworkClient().newBuilder().proxy(Proxy.NO_PROXY).build()
        try {
            val search = Request.Builder()
                .url("https://movie.douban.com/j/subject_suggest?q=%E5%8D%83%E4%B8%8E%E5%8D%83%E5%AF%BB")
                .header("User-Agent", "Mozilla/5.0").build()
            client.newCall(search).execute().use { response ->
                assertEquals(200, response.code)
                assertTrue(response.body!!.string().contains("1291561"))
            }
            var imageUrl = ""
            val photos = Request.Builder()
                .url("https://m.douban.com/rexxar/api/v2/movie/1291561/photos?start=0&count=12")
                .header("Referer", "https://m.douban.com/")
                .header("User-Agent", "Mozilla/5.0").build()
            client.newCall(photos).execute().use { response ->
                assertEquals(200, response.code)
                imageUrl = JSONObject(response.body!!.string()).getJSONArray("photos")
                    .getJSONObject(0).getJSONObject("image").getJSONObject("normal").getString("url")
            }
            val image = Request.Builder().url(imageUrl)
                .header("Referer", "https://m.douban.com/").header("User-Agent", "Mozilla/5.0").build()
            client.newCall(image).execute().use { response ->
                assertEquals(200, response.code)
                assertTrue(response.header("Content-Type").orEmpty().startsWith("image/"))
                assertTrue(response.body!!.bytes().isNotEmpty())
            }
        } finally {
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }

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
