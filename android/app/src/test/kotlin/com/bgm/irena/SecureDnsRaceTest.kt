package com.bgm.irena

import okhttp3.Call
import okhttp3.Callback
import okhttp3.Request
import okhttp3.Response
import okhttp3.Protocol
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Timeout
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class SecureDnsRaceTest {
    private val valid = """{"Status":0,"Question":[{"name":"next.bgm.tv","type":1}],"Answer":[{"type":1,"TTL":60,"data":"8.8.8.8"}]}"""

    private class FakeCall(private val delayMs: Long, private val body: String) : Call {
        @Volatile private var cancelled = false
        private val cancellation = CountDownLatch(1)
        override fun request() = Request.Builder().url("https://resolver.example/resolve").build()
        override fun execute(): Response = error("async only")
        override fun enqueue(responseCallback: Callback) {
            Thread {
                if (cancellation.await(delayMs, TimeUnit.MILLISECONDS)) responseCallback.onFailure(this, IOException("cancelled"))
                else responseCallback.onResponse(this, Response.Builder().request(request())
                    .protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toResponseBody()).build())
            }.apply { isDaemon = true; start() }
        }
        override fun cancel() { cancelled = true; cancellation.countDown() }
        override fun isExecuted() = true
        override fun isCanceled() = cancelled
        override fun timeout() = Timeout()
        override fun clone(): Call = FakeCall(delayMs, body)
    }

    @Test fun fastValidAnswerWinsAndOutstandingCallsAreCancelled() {
        val calls = listOf(FakeCall(1000, valid), FakeCall(5, valid))
        val start = System.nanoTime()
        assertEquals(listOf("8.8.8.8"), raceDnsAnswers("next.bgm.tv", calls, 250)?.addresses)
        assertTrue(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start) < 800)
        assertTrue(calls.all { it.isCanceled() })
    }

    @Test fun invalidAnswerDoesNotDefeatSlowerValidAnswer() {
        val calls = listOf(FakeCall(5, valid.replace("next.bgm.tv", "evil.example")), FakeCall(30, valid))
        assertNotNull(raceDnsAnswers("next.bgm.tv", calls, 250))
        assertTrue(calls.all { it.isCanceled() })
    }

    @Test fun deadlineReturnsFallbackSignalAndCancelsEveryCall() {
        val calls = listOf(FakeCall(1000, valid), FakeCall(1000, valid))
        assertNull(raceDnsAnswers("next.bgm.tv", calls, 30))
        assertTrue(calls.all { it.isCanceled() })
    }
}
