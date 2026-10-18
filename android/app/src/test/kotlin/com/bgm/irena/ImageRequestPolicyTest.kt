package com.bgm.irena

import okhttp3.Request
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ImageRequestPolicyTest {
    private fun request(url: String) = Request.Builder().url(url)
        .header("Cookie", "synthetic").header("Authorization", "synthetic")
        .header("Proxy-Authorization", "synthetic").header("Referer", "https://private.example/")
        .build()

    @Test fun onlyRealDoubanHostsReceiveFixedPublicReferer() {
        for (host in listOf("doubanio.com", "img9.doubanio.com")) {
            val safe = anonymousImageRequest(request("https://$host/a.jpg"))
            assertEquals("https://m.douban.com/", safe.header("Referer"))
            assertEquals("Mozilla/5.0", safe.header("User-Agent"))
            assertNull(safe.header("Cookie"))
            assertNull(safe.header("Authorization"))
            assertNull(safe.header("Proxy-Authorization"))
        }
        for (host in listOf("example.com", "evildoubanio.com", "doubanio.com.example.com")) {
            assertNull(anonymousImageRequest(request("https://$host/a.jpg")).header("Referer"))
        }
    }

    @Test fun redirectLeavingDoubanDropsRefererAndCredentials() {
        val first = anonymousImageRequest(request("https://img9.doubanio.com/a.jpg"))
        val redirected = anonymousImageRequest(first.newBuilder().url("https://example.com/a.jpg").build())
        assertNull(redirected.header("Referer"))
        assertNull(redirected.header("Cookie"))
        assertNull(redirected.header("Authorization"))
        val returning = anonymousImageRequest(redirected.newBuilder().url("https://img3.doubanio.com/a.jpg").build())
        assertEquals("https://m.douban.com/", returning.header("Referer"))
    }
}
