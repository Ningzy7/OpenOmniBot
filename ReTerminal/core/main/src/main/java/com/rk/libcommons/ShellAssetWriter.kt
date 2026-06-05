package com.rk.libcommons

import android.content.Context
import java.io.File

object ShellAssetWriter {
    fun writeExecutableShellAsset(context: Context, assetName: String, target: File) {
        writeShellAsset(context, assetName, target)
        target.setExecutable(true, false)
    }

    fun writeShellAsset(context: Context, assetName: String, target: File) {
        target.parentFile?.mkdirs()
        val content = context.assets.open(assetName).bufferedReader().use { reader ->
            reader.readText()
        }.normalizeShellLineEndings()
        if (!target.exists() || target.readText().normalizeShellLineEndings() != content) {
            target.writeText(content)
        }
        target.setReadable(true, false)
    }

    private fun String.normalizeShellLineEndings(): String {
        return replace("\r\n", "\n").replace('\r', '\n')
    }
}
