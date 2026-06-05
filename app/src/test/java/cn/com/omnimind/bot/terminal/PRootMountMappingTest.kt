package cn.com.omnimind.bot.terminal

import com.ai.assistance.operit.terminal.provider.filesystem.PRootMountMapping
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class PRootMountMappingTest {
    @Test
    fun resolveSoftMountedSourcePathMapsWorkspaceToInternalAppRoot() {
        val mapped = PRootMountMapping.resolveSoftMountedSourcePath(
            linuxPath = "/workspace/demo/app.py",
            homeDir = "/data/user/0/cn.com.omnimind.bot/files",
            workspaceDir = "/data/user/0/cn.com.omnimind.bot/workspace",
            appDataDir = "/data/user/0/cn.com.omnimind.bot",
            packageName = "cn.com.omnimind.bot",
            chrootEnabled = false
        )

        assertEquals(
            "/data/user/0/cn.com.omnimind.bot/workspace/demo/app.py",
            mapped
        )
    }

    @Test
    fun mapLinuxPathToHostPathKeepsHomeDirDistinctFromWorkspace() {
        val hostPath = PRootMountMapping.mapLinuxPathToHostPath(
            linuxPath = "/data/user/0/cn.com.omnimind.bot/files/tmp.txt",
            rootfsRoot = File("/tmp/fake-rootfs"),
            homeDir = "/data/user/0/cn.com.omnimind.bot/files",
            workspaceDir = "/data/user/0/cn.com.omnimind.bot/workspace",
            appDataDir = "/data/user/0/cn.com.omnimind.bot",
            packageName = "cn.com.omnimind.bot",
            chrootEnabled = false
        )

        assertEquals(
            "/data/user/0/cn.com.omnimind.bot/files/tmp.txt",
            hostPath
        )
    }

    @Test
    fun mapLinuxPathToHostPathMapsMtManagerStorageMounts() {
        val mountPath = PRootMountMapping.mapLinuxPathToHostPath(
            linuxPath = "/mnt/mt/projects/demo.txt",
            rootfsRoot = File("/tmp/fake-rootfs"),
            homeDir = "/data/user/0/cn.com.omnimind.bot/files",
            workspaceDir = "/data/user/0/cn.com.omnimind.bot/workspace",
            appDataDir = "/data/user/0/cn.com.omnimind.bot",
            packageName = "cn.com.omnimind.bot",
            chrootEnabled = false
        )
        val shortcutPath = PRootMountMapping.mapLinuxPathToHostPath(
            linuxPath = "/mt/projects/demo.txt",
            rootfsRoot = File("/tmp/fake-rootfs"),
            homeDir = "/data/user/0/cn.com.omnimind.bot/files",
            workspaceDir = "/data/user/0/cn.com.omnimind.bot/workspace",
            appDataDir = "/data/user/0/cn.com.omnimind.bot",
            packageName = "cn.com.omnimind.bot",
            chrootEnabled = false
        )

        assertEquals(
            "/sdcard/projects/demo.txt",
            mountPath
        )
        assertEquals(mountPath, shortcutPath)
    }
}
