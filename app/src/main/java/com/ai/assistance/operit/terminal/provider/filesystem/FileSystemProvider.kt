package com.ai.assistance.operit.terminal.provider.filesystem

import com.rk.libcommons.OmnibotTerminalEnvironment
import java.io.File

data class PRootBindMount(
    val sourcePath: String,
    val targetPath: String = sourcePath
)

object PRootMountMapping {
    private val baseBindMounts: List<PRootBindMount> = listOf(
        PRootBindMount("/dev"),
        PRootBindMount("/proc"),
        PRootBindMount("/sys"),
        PRootBindMount("/dev/pts"),
        PRootBindMount("/proc/self/fd", "/dev/fd"),
        PRootBindMount("/proc/self/fd/0", "/dev/stdin"),
        PRootBindMount("/proc/self/fd/1", "/dev/stdout"),
        PRootBindMount("/proc/self/fd/2", "/dev/stderr"),
        PRootBindMount("/storage/emulated/0", "/sdcard"),
        PRootBindMount("/storage/emulated/0", "/storage/emulated/0"),
        PRootBindMount("/data/local/tmp", "/data/local/tmp"),
        PRootBindMount(
            OmnibotTerminalEnvironment.mtStorageHostPath(),
            OmnibotTerminalEnvironment.mtStorageMountPath()
        ),
        PRootBindMount(
            OmnibotTerminalEnvironment.mtStorageHostPath(),
            OmnibotTerminalEnvironment.mtStorageShortcutPath()
        )
    )

    private fun buildDataBindMounts(
        appDataDir: String,
        packageName: String,
        chrootEnabled: Boolean
    ): List<PRootBindMount> {
        return if (chrootEnabled) {
            listOf(
                PRootBindMount("/data/user/0", "/data/user/0"),
                PRootBindMount("/data/data", "/data/data")
            )
        } else {
            listOf(
                PRootBindMount(appDataDir, "/data/user/0/$packageName"),
                PRootBindMount(appDataDir, "/data/data/$packageName")
            )
        }
    }

    fun buildRuntimeBindMounts(
        homeDir: String,
        workspaceDir: String,
        appDataDir: String,
        packageName: String,
        chrootEnabled: Boolean
    ): List<PRootBindMount> {
        return baseBindMounts +
            PRootBindMount(workspaceDir, "/workspace") +
            buildDataBindMounts(appDataDir, packageName, chrootEnabled) +
            PRootBindMount(homeDir, homeDir)
    }

    fun mapLinuxPathToHostPath(
        linuxPath: String,
        rootfsRoot: File,
        homeDir: String,
        workspaceDir: String,
        appDataDir: String,
        packageName: String,
        chrootEnabled: Boolean
    ): String {
        val normalizedPath = normalizeLinuxPath(linuxPath)
        resolveSoftMountedSourcePath(
            linuxPath = normalizedPath,
            homeDir = homeDir,
            workspaceDir = workspaceDir,
            appDataDir = appDataDir,
            packageName = packageName,
            chrootEnabled = chrootEnabled
        )?.let { return it }

        if (normalizedPath == "/") {
            return rootfsRoot.absolutePath
        }
        return File(rootfsRoot, normalizedPath.trimStart('/')).absolutePath
    }

    fun resolveSoftMountedSourcePath(
        linuxPath: String,
        homeDir: String,
        workspaceDir: String,
        appDataDir: String,
        packageName: String,
        chrootEnabled: Boolean
    ): String? {
        val normalizedPath = normalizeLinuxPath(linuxPath)
        val mounts = buildRuntimeBindMounts(
            homeDir = homeDir,
            workspaceDir = workspaceDir,
            appDataDir = appDataDir,
            packageName = packageName,
            chrootEnabled = chrootEnabled
        ).sortedByDescending { normalizeLinuxPath(it.targetPath).length }

        for (mount in mounts) {
            val normalizedTarget = normalizeLinuxPath(mount.targetPath)
            val isExactMatch = normalizedPath == normalizedTarget
            val isChildPath = normalizedPath.startsWith("$normalizedTarget/")
            if (!isExactMatch && !isChildPath) {
                continue
            }

            val relativeSuffix = normalizedPath.removePrefix(normalizedTarget).trimStart('/')
            val normalizedSource = normalizeLinuxPath(mount.sourcePath)
            return if (relativeSuffix.isEmpty()) {
                normalizedSource
            } else {
                "$normalizedSource/$relativeSuffix"
            }
        }

        return null
    }

    private fun normalizeLinuxPath(path: String): String {
        val trimmed = path.trim()
        if (trimmed.isEmpty()) return "/"
        val slashNormalized = trimmed.replace('\\', '/')
        val withLeadingSlash = if (slashNormalized.startsWith('/')) slashNormalized else "/$slashNormalized"
        return if (withLeadingSlash.length > 1) withLeadingSlash.trimEnd('/') else withLeadingSlash
    }
}
