package com.bgm.irena

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

class ImageAddressSafetyTest {
    @Test fun rejectsLocalAndMetadataDestinations() {
        for (value in listOf("0.0.0.0", "127.0.0.1", "10.0.0.1", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1", "::1", "fc00::1", "fe80::1")) {
            assertFalse(value, BangumiNetworkBridge.isPublicImageAddress(InetAddress.getByName(value)))
        }
    }

    @Test fun acceptsPublicIpv4AndIpv6() {
        assertTrue(BangumiNetworkBridge.isPublicImageAddress(InetAddress.getByName("93.184.216.34")))
        assertTrue(BangumiNetworkBridge.isPublicImageAddress(InetAddress.getByName("2606:4700:4700::1111")))
    }
}
