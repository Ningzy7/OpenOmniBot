import java.math.BigInteger
import java.net.URI
import java.io.RandomAccessFile
import java.security.MessageDigest
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

val gitCommitHash: Provider<String> =
    providers.exec { commandLine("git", "rev-parse", "--short=8", "HEAD") }.standardOutput.asText.map { it.trim() }

val fullGitCommitHash: Provider<String> =
    providers.exec { commandLine("git", "rev-parse", "HEAD") }.standardOutput.asText.map { it.trim() }

val gitCommitDate: Provider<String> =
    providers.exec { commandLine("git", "show", "-s", "--format=%cI", "HEAD") }.standardOutput.asText.map { it.trim() }

val termuxPackageBaseUrl = "https://packages-cf.termux.dev/apt/termux-main"
val prootDebUrl = "$termuxPackageBaseUrl/pool/main/p/proot/proot_5.1.107.74_aarch64.deb"
val prootDebChecksum = "6e3b76e2b3d16922e57ae69e771e708ab7ea84ec9d241f268a2046ab417ff0a7"
val libtallocDebUrl = "$termuxPackageBaseUrl/pool/main/libt/libtalloc/libtalloc_2.4.3_aarch64.deb"
val libtallocDebChecksum = "ac81ad623d74c209718b9f3acb2dd702cc8a88c431e820d212229910b4db29da"
val alpineMiniRootfsUrl =
    "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.0-aarch64.tar.gz"
val alpineMiniRootfsChecksum = "f31202c4070c4ef7de9e157e1bd01cb4da3a2150035d74ea5372c5e86f1efac1"

android {
    namespace = "com.rk.terminal"
    android.buildFeatures.buildConfig = true
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(layout.buildDirectory.dir("generated/jniLibs/embeddedTerminalRuntime"))
            assets.srcDir(layout.buildDirectory.dir("generated/assets/embeddedTerminalRuntime"))
        }
    }

    buildTypes {
        release {
            buildConfigField("String", "GIT_COMMIT_HASH", "\"${fullGitCommitHash.get()}\"")
            buildConfigField("String", "GIT_SHORT_COMMIT_HASH", "\"${gitCommitHash.get()}\"")
            buildConfigField("String", "GIT_COMMIT_DATE", "\"${gitCommitDate.get()}\"")

            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"
            )
        }
        debug{
            buildConfigField("String", "GIT_COMMIT_HASH", "\"${fullGitCommitHash.get()}\"")
            buildConfigField("String", "GIT_SHORT_COMMIT_HASH", "\"${gitCommitHash.get()}\"")
            buildConfigField("String", "GIT_COMMIT_DATE", "\"${gitCommitDate.get()}\"")
        }
    }


    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        viewBinding = true
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.15"
    }


}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(8192)
        while (true) {
            val readBytes = input.read(buffer)
            if (readBytes < 0) break
            digest.update(buffer, 0, readBytes)
        }
    }
    return BigInteger(1, digest.digest()).toString(16).padStart(64, '0')
}

fun downloadRuntimeFile(localPath: String, remoteUrl: String, expectedChecksum: String? = null) {
    val file = file(localPath)
    if (file.exists()) {
        val checksum = sha256(file)
        if (expectedChecksum == null || checksum == expectedChecksum) return
        file.delete()
    }

    file.parentFile?.mkdirs()
    val digest = MessageDigest.getInstance("SHA-256")
    val connection = URI(remoteUrl).toURL().openConnection()
    connection.getInputStream().use { input ->
        file.outputStream().use { output ->
            val buffer = ByteArray(8192)
            while (true) {
                val readBytes = input.read(buffer)
                if (readBytes < 0) break
                output.write(buffer, 0, readBytes)
                digest.update(buffer, 0, readBytes)
            }
        }
    }
    var checksum = BigInteger(1, digest.digest()).toString(16)
    while (checksum.length < 64) checksum = "0$checksum"
    if (expectedChecksum != null && checksum != expectedChecksum) {
        file.delete()
        throw GradleException(
            "Wrong checksum for $remoteUrl:\nExpected: $expectedChecksum\nActual:   $checksum"
        )
    }
}

fun extractDebMember(debFile: File, memberName: String, target: File) {
    target.parentFile?.mkdirs()
    RandomAccessFile(debFile, "r").use { input ->
        val globalHeader = ByteArray(8)
        input.readFully(globalHeader)
        check(String(globalHeader) == "!<arch>\n") { "Invalid deb archive: ${debFile.absolutePath}" }

        while (input.filePointer < input.length()) {
            val header = ByteArray(60)
            input.readFully(header)
            val name = String(header, 0, 16).trim().removeSuffix("/")
            val size = String(header, 48, 10).trim().toLong()
            if (name == memberName) {
                target.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var remaining = size
                    while (remaining > 0) {
                        val readBytes = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                        check(readBytes >= 0) { "Unexpected EOF while reading $memberName from ${debFile.name}" }
                        output.write(buffer, 0, readBytes)
                        remaining -= readBytes
                    }
                }
                return
            }
            input.seek(input.filePointer + size + (size % 2))
        }
    }
    error("Missing $memberName in ${debFile.absolutePath}")
}

fun unpackDebData(debFile: File, targetDir: File) {
    val dataArchive = File(targetDir.parentFile, "${debFile.name}.data.tar.xz")
    extractDebMember(debFile, "data.tar.xz", dataArchive)
    targetDir.deleteRecursively()
    targetDir.mkdirs()
    exec {
        commandLine("tar", "-xJf", dataArchive.absolutePath, "-C", targetDir.absolutePath)
    }
}

fun copyRuntimeFile(source: File, target: File, executable: Boolean) {
    check(source.isFile && source.length() > 0) { "Missing runtime file: ${source.absolutePath}" }
    target.parentFile?.mkdirs()
    source.copyTo(target, overwrite = true)
    target.setReadable(true, false)
    target.setWritable(true, true)
    if (executable) {
        target.setExecutable(true, false)
    }
}

val prepareEmbeddedTerminalRuntime by tasks.registering {
    val outputDir = layout.buildDirectory.dir("generated/assets/embeddedTerminalRuntime/embedded-terminal-runtime")
    val jniOutputDir = layout.buildDirectory.dir("generated/jniLibs/embeddedTerminalRuntime")
    inputs.property("prootDebUrl", prootDebUrl)
    inputs.property("prootDebChecksum", prootDebChecksum)
    inputs.property("libtallocDebUrl", libtallocDebUrl)
    inputs.property("libtallocDebChecksum", libtallocDebChecksum)
    inputs.property("alpineMiniRootfsUrl", alpineMiniRootfsUrl)
    inputs.property("alpineMiniRootfsChecksum", alpineMiniRootfsChecksum)
    outputs.dir(outputDir)
    outputs.dir(jniOutputDir)
    doLast {
        val root = outputDir.get().asFile
        val jniRoot = jniOutputDir.get().asFile
        root.mkdirs()
        jniRoot.mkdirs()
        val workDir = temporaryDir.apply {
            deleteRecursively()
            mkdirs()
        }

        val prootDeb = workDir.resolve("proot.deb")
        downloadRuntimeFile(
            localPath = prootDeb.absolutePath,
            remoteUrl = prootDebUrl,
            expectedChecksum = prootDebChecksum
        )
        val prootPackageRoot = workDir.resolve("proot")
        unpackDebData(prootDeb, prootPackageRoot)
        val prootPrefix = prootPackageRoot.resolve("data/data/com.termux/files/usr")
        copyRuntimeFile(
            source = prootPrefix.resolve("bin/proot"),
            target = root.resolve("proot"),
            executable = true
        )
        copyRuntimeFile(
            source = prootPrefix.resolve("libexec/proot/loader"),
            target = jniRoot.resolve("arm64-v8a/libproot-loader.so"),
            executable = true
        )
        copyRuntimeFile(
            source = prootPrefix.resolve("libexec/proot/loader32"),
            target = jniRoot.resolve("arm64-v8a/libproot-loader32.so"),
            executable = true
        )

        val libtallocDeb = workDir.resolve("libtalloc.deb")
        downloadRuntimeFile(
            localPath = libtallocDeb.absolutePath,
            remoteUrl = libtallocDebUrl,
            expectedChecksum = libtallocDebChecksum
        )
        val libtallocPackageRoot = workDir.resolve("libtalloc")
        unpackDebData(libtallocDeb, libtallocPackageRoot)
        copyRuntimeFile(
            source = libtallocPackageRoot.resolve("data/data/com.termux/files/usr/lib/libtalloc.so.2.4.3"),
            target = root.resolve("libtalloc.so.2"),
            executable = false
        )

        downloadRuntimeFile(
            localPath = root.resolve("alpine.tar.gz").absolutePath,
            remoteUrl = alpineMiniRootfsUrl,
            expectedChecksum = alpineMiniRootfsChecksum
        )
    }
}

tasks.named("preBuild") {
    dependsOn(prepareEmbeddedTerminalRuntime)
}


dependencies {
    api(libs.appcompat)
    api(libs.material)
    api(libs.constraintlayout)
    api(libs.navigation.fragment)
    api(libs.navigation.ui)
    api(libs.navigation.fragment.ktx)
    api(libs.navigation.ui.ktx)
    api(libs.activity)
    api(libs.lifecycle.viewmodel.ktx)
    api(libs.lifecycle.runtime.ktx)
    api(libs.activity.compose)
    api(platform(libs.compose.bom))
    api(libs.ui)
    api(libs.ui.graphics)
    api(libs.material3)
    api(libs.navigation.compose)
    api(project(":core:terminal-view"))
    api(project(":core:terminal-emulator"))
    api(libs.utilcode)
    //api(libs.commons.net)
    api(libs.okhttp)
    api(libs.anrwatchdog)
    api(libs.androidx.material.icons.core)
    api(libs.androidx.palette)
    api(libs.accompanist.systemuicontroller)
//    api(libs.termux.shared)

    api(project(":core:resources"))
    api(project(":core:components"))
}
