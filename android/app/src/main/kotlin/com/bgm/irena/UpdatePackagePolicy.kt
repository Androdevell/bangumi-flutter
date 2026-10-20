package com.bgm.irena

/**
 * 只接受本应用、不降级且具有可信签名身份的更新包；最终安装仍由系统校验。
 */
internal object UpdatePackagePolicy {
    fun accepts(
        installedPackage: String, candidatePackage: String,
        installedVersion: Long, candidateVersion: Long,
        installedSigners: Set<String>, candidateSigners: Set<String>,
        candidateHistory: Set<String>,
    ): Boolean {
        if (installedPackage != candidatePackage || candidateVersion < installedVersion ||
            installedSigners.isEmpty() || candidateSigners.isEmpty()) return false
        if (installedSigners == candidateSigners) return true
        return installedSigners.size == 1 && candidateSigners.size == 1 &&
            candidateHistory.containsAll(installedSigners)
    }
}
