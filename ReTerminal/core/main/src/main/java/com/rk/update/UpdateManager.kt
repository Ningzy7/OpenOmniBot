package com.rk.update

import com.rk.libcommons.application
import com.rk.libcommons.child
import com.rk.libcommons.createFileIfNot
import com.rk.libcommons.localBinDir
import com.rk.libcommons.ShellAssetWriter
import java.io.File

class UpdateManager {
    fun onUpdate(){
        val initFile: File = localBinDir().child("init-host")
        if(initFile.exists()){
            initFile.delete()
        }

        if (initFile.exists().not()){
            initFile.createFileIfNot()
            ShellAssetWriter.writeExecutableShellAsset(application!!, "init-host.sh", initFile)
        }

        val initFilex: File = localBinDir().child("init")
        if(initFilex.exists()){
            initFilex.delete()
        }

        if (initFilex.exists().not()){
            initFilex.createFileIfNot()
            ShellAssetWriter.writeExecutableShellAsset(application!!, "init.sh", initFilex)
        }
    }
}
