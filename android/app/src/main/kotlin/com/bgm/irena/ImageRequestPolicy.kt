package com.bgm.irena

import okhttp3.Request

/**
 * 每一跳图片下载都剥离凭证，仅为豆瓣图床设置固定公开来源。
 *
 * @param original 当前跳转目标的请求，不信任调用者提供的来源标头
 */
internal fun anonymousImageRequest(original: Request): Request {
    val builder = original.newBuilder()
        .removeHeader("Cookie").removeHeader("Authorization")
        .removeHeader("Proxy-Authorization").removeHeader("Referer")
    val url = original.url
    if (url.isHttps && url.port == 443 && url.username.isEmpty() && url.password.isEmpty() &&
        (url.host == "doubanio.com" || url.host.endsWith(".doubanio.com"))) {
        builder.header("Referer", "https://m.douban.com/")
            .header("User-Agent", "Mozilla/5.0")
    }
    return builder.build()
}
