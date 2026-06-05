package cn.com.omnimind.bot.terminal

import android.content.Context
import android.content.Intent
import android.util.Log
import com.ai.assistance.operit.terminal.setup.EnvironmentSetupLogic
import com.rk.libcommons.OMNIBOT_SETUP_SESSION_ID
import com.rk.libcommons.ShellArgv
import com.rk.libcommons.TerminalCommand
import com.rk.libcommons.pendingCommand
import com.rk.terminal.ui.activities.terminal.MainActivity as ReTerminalMainActivity
import com.rk.terminal.ui.screens.settings.WorkingMode
import java.io.File

object EmbeddedTerminalLaunchHelper {
    private const val TAG = "EmbeddedTerminalLaunch"

    fun launch(
        context: Context,
        openSetup: Boolean = false,
        setupPackageIds: List<String> = emptyList()
    ) {
        preparePendingCommand(
            context = context,
            openSetup = openSetup,
            setupPackageIds = setupPackageIds
        )
        context.startActivity(
            Intent(context, ReTerminalMainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }

    fun preparePendingCommand(
        context: Context,
        openSetup: Boolean = false,
        setupPackageIds: List<String> = emptyList()
    ) {
        pendingCommand = null
        if (!openSetup) {
            return
        }

        val selectedPackageIds = setupPackageIds
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
        if (selectedPackageIds.isEmpty()) {
            return
        }

        val commands = EnvironmentSetupLogic.buildInstallCommands(
            selectedPackageIds = selectedPackageIds,
            repositorySetupCommand = ""
        )
        if (commands.isEmpty()) {
            return
        }

        val installScriptPath = prepareSetupScript(context, commands, selectedPackageIds)
        val initHostPath = File(context.filesDir.parentFile, "local/bin/init-host").absolutePath

        pendingCommand = TerminalCommand(
            shell = ShellArgv.SYSTEM_SH,
            args = ShellArgv.buildShellScriptArgv(
                initHostPath,
                "/bin/sh",
                installScriptPath
            ),
            id = OMNIBOT_SETUP_SESSION_ID,
            workingMode = WorkingMode.ALPINE,
            terminatePreviousSession = true,
            workingDir = "/"
        )
        Log.d(
            TAG,
            "Prepared setup session ${ShellArgv.formatExecSpec(ShellArgv.SYSTEM_SH, pendingCommand!!.args, "/")}"
        )
    }

    private fun prepareSetupScript(
        context: Context,
        commands: List<String>,
        selectedPackageIds: List<String>
    ): String {
        val scriptFile = File(context.filesDir.parentFile, "local/bin/omni-setup.sh").apply {
            parentFile?.mkdirs()
        }
        val content = EnvironmentSetupLogic.buildSetupScript(commands, selectedPackageIds)
        scriptFile.writeText(content)
        scriptFile.setExecutable(true, false)
        return scriptFile.absolutePath
    }
}
