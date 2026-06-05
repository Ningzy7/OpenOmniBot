package cn.com.omnimind.bot.agent

import cn.com.omnimind.assists.controller.http.HttpController
import cn.com.omnimind.baselib.llm.MnnLocalProviderStateStore
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentToolImageContinuationPolicyResolverTest {
    @After
    fun tearDown() {
        MnnLocalProviderStateStore.setEnabled(false)
    }

    @Test
    fun mimoRouteDisablesToolImageContinuation() {
        val routeInfo = HttpController.ChatCompletionRouteInfo(
            requestedModel = "scene.dispatch.model",
            resolvedModel = "mimo-v2.5",
            apiBase = "https://relay.example.com/v1",
            providerProfileId = "profile-1",
            providerProfileName = "Provider 1",
            routeTag = "custom_openai_compat",
            bindingApplied = false,
            bindingProfileMissing = false,
            overrideApplied = true,
            protocolType = "openai_compatible"
        )

        val policy = AgentToolImageContinuationPolicyResolver.resolve(routeInfo)

        assertFalse(policy.supportsToolImageContinuation)
    }

    @Test
    fun builtinLocalProviderStaysEnabledEvenIfModelNameContainsMimo() {
        MnnLocalProviderStateStore.setEnabled(true)
        val routeInfo = HttpController.ChatCompletionRouteInfo(
            requestedModel = "scene.dispatch.model",
            resolvedModel = "MiMo-7B-RL-MNN",
            apiBase = "http://127.0.0.1:8080",
            providerProfileId = MnnLocalProviderStateStore.BUILTIN_PROFILE_ID,
            providerProfileName = MnnLocalProviderStateStore.BUILTIN_PROFILE_NAME,
            routeTag = "custom_openai_compat",
            bindingApplied = false,
            bindingProfileMissing = false,
            overrideApplied = true,
            protocolType = "openai_compatible"
        )

        val policy = AgentToolImageContinuationPolicyResolver.resolve(routeInfo)

        assertTrue(policy.supportsToolImageContinuation)
    }
}
