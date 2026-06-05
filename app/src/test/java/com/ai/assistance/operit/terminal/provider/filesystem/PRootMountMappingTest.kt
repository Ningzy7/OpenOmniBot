package com.ai.assistance.operit.terminal.provider.filesystem

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class PRootMountMappingTest {

    @Test
    fun mapLinuxPathToHostPath_mapsRootfsAndWorkspacePaths() {
        val rootfsRoot = File("/tmp/alpine-rootfs")
        val homeDir = "/data/user/0/cn.com.omnimind.bot/files"
        val workspaceDir = "/data/user/0/cn.com.omnimind.bot/workspace"
        val appDataDir = "/data/user/0/cn.com.omnimind.bot"
        val packageName = "cn.com.omnimind.bot"

        assertEquals(
            rootfsRoot.absolutePath,
            PRootMountMapping.mapLinuxPathToHostPath(
                linuxPath = "/",
                rootfsRoot = rootfsRoot,
                homeDir = homeDir,
                workspaceDir = workspaceDir,
                appDataDir = appDataDir,
                packageName = packageName,
                chrootEnabled = false
            )
        )

        assertEquals(
            "$workspaceDir/project/file.txt",
            PRootMountMapping.mapLinuxPathToHostPath(
                linuxPath = "/workspace/project/file.txt",
                rootfsRoot = rootfsRoot,
                homeDir = homeDir,
                workspaceDir = workspaceDir,
                appDataDir = appDataDir,
                packageName = packageName,
                chrootEnabled = false
            )
        )
    }

    @Test
    fun mapLinuxPathToHostPath_mapsRegularLinuxPathsIntoRootfs() {
        val rootfsRoot = File("/tmp/alpine-rootfs")

        assertEquals(
            File(rootfsRoot, "usr/local/bin/node").absolutePath,
            PRootMountMapping.mapLinuxPathToHostPath(
                linuxPath = "/usr/local/bin/node",
                rootfsRoot = rootfsRoot,
                homeDir = "/home/root",
                workspaceDir = "/workspace-host",
                appDataDir = "/data/user/0/cn.com.omnimind.bot",
                packageName = "cn.com.omnimind.bot",
                chrootEnabled = false
            )
        )
    }

    @Test
    fun mapLinuxPathToHostPath_mapsMtStorageMounts() {
        val rootfsRoot = File("/tmp/alpine-rootfs")

        assertEquals(
            "/sdcard/notes/a.txt",
            PRootMountMapping.mapLinuxPathToHostPath(
                linuxPath = "/mnt/mt/notes/a.txt",
                rootfsRoot = rootfsRoot,
                homeDir = "/home/root",
                workspaceDir = "/workspace-host",
                appDataDir = "/data/user/0/cn.com.omnimind.bot",
                packageName = "cn.com.omnimind.bot",
                chrootEnabled = false
            )
        )
    }
}
