package cn.com.omnimind.bot.activity

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.ai.assistance.operit.terminal.TerminalManager
import com.ai.assistance.operit.terminal.setup.EnvironmentSetupLogic
import cn.com.omnimind.bot.terminal.EmbeddedTerminalRuntime
import com.rk.libcommons.ShellArgv
import com.rk.libcommons.TerminalCommand
import com.rk.libcommons.pendingCommand
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.rk.terminal.ui.screens.settings.WorkingMode
import kotlinx.coroutines.launch
import java.io.File

class TerminalActivity : ComponentActivity() {
    companion object {
        private const val TAG = "TerminalActivity"
        const val EXTRA_OPEN_SETUP = "open_setup"
        const val EXTRA_SETUP_PACKAGE_IDS = "setup_package_ids"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingCommand = null
        lifecycleScope.launch {
            runCatching {
                EmbeddedTerminalRuntime.warmup(this@TerminalActivity)
                TerminalManager.getInstance(this@TerminalActivity).initializeEnvironment()
            }
            configurePendingSetupSession()
            startActivity(
                Intent(this@TerminalActivity, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(EXTRA_OPEN_SETUP, intent?.getBooleanExtra(EXTRA_OPEN_SETUP, false) == true)
                }
            )
            finish()
        }
    }

    private fun configurePendingSetupSession() {
        val openSetup = intent?.getBooleanExtra(EXTRA_OPEN_SETUP, false) == true
        if (!openSetup) {
            return
        }
        val selectedPackageIds = intent
            ?.getStringArrayListExtra(EXTRA_SETUP_PACKAGE_IDS)
            .orEmpty()
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

        val initHostPath = File(filesDir.parentFile, "local/bin/init-host").absolutePath
        val installScriptPath = prepareSetupScript(commands, selectedPackageIds)

        pendingCommand = TerminalCommand(
            shell = ShellArgv.SYSTEM_SH,
            args = ShellArgv.buildShellScriptArgv(initHostPath, "/bin/sh", installScriptPath),
            id = "setup-${System.currentTimeMillis()}",
            workingMode = WorkingMode.ALPINE,
            terminatePreviousSession = false,
            workingDir = "/"
        )
        Log.d(
            TAG,
            "Prepared setup session ${ShellArgv.formatExecSpec(ShellArgv.SYSTEM_SH, pendingCommand!!.args, "/")}"
        )
    }

    private fun prepareSetupScript(commands: List<String>, selectedPackageIds: List<String>): String {
        val scriptFile = File(filesDir.parentFile, "local/bin/omni-setup.sh").apply {
            parentFile?.mkdirs()
        }
        val content = EnvironmentSetupLogic.buildSetupScript(commands, selectedPackageIds)
        scriptFile.writeText(content)
        scriptFile.setExecutable(true, false)
        return scriptFile.absolutePath
    }
}
