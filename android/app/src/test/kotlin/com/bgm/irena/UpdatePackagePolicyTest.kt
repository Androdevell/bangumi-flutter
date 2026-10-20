package com.bgm.irena

import org.junit.Assert.*
import org.junit.Test

class UpdatePackagePolicyTest {
    @Test fun rejectsForeignPackageDowngradeAndUnknownSigner() {
        fun accepts(pkg: String = "com.bgm.irena", version: Long = 2030,
                    signer: Set<String> = setOf("original"), history: Set<String> = emptySet()) =
            UpdatePackagePolicy.accepts("com.bgm.irena", pkg, 2029, version, setOf("original"), signer, history)
        assertTrue(accepts())
        assertFalse(accepts(pkg = "foreign.app"))
        assertFalse(accepts(version = 2028))
        assertFalse(accepts(signer = setOf("unknown")))
        assertFalse(accepts(signer = emptySet()))
        assertTrue(accepts(signer = setOf("rotated"), history = setOf("original", "rotated")))
    }
}
