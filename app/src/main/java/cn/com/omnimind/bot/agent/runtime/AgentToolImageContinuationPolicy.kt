package cn.com.omnimind.bot.agent

import cn.com.omnimind.assists.controller.http.HttpController
import cn.com.omnimind.baselib.llm.LocalModelProviderBridge
import java.util.Locale

data class AgentToolImageContinuationPolicy(
    val supportsToolImageContinuation: Boolean,
    val routeLabel: String = "unknown"
) {
    companion object {
        val DEFAULT = AgentToolImageContinuationPolicy(
            supportsToolImageContinuation = true
        )
    }
}

object AgentToolImageContinuationPolicyResolver {
    fun resolve(
        routeInfo: HttpController.ChatCompletionRouteInfo?
    ): AgentToolImageContinuationPolicy {
        if (routeInfo == null) {
            return AgentToolImageContinuationPolicy.DEFAULT
        }
        val routeLabel = buildRouteLabel(routeInfo)
        if (LocalModelProviderBridge.isBuiltinLocalProvider(routeInfo.providerProfileId, routeInfo.apiBase)) {
            return AgentToolImageContinuationPolicy(
                supportsToolImageContinuation = true,
                routeLabel = routeLabel
            )
        }
        return AgentToolImageContinuationPolicy(
            supportsToolImageContinuation = !isKnownIncompatibleRoute(routeInfo),
            routeLabel = routeLabel
        )
    }

    // TODO(issue321): replace this route heuristic with provider capability flags once
    // Mimo becomes a first-class builtin provider profile.
    private fun isKnownIncompatibleRoute(
        routeInfo: HttpController.ChatCompletionRouteInfo
    ): Boolean {
        return candidateTokens(routeInfo).any { token ->
            token.contains("xiaomi") ||
                token.startsWith("mimo-") ||
                token.contains("/mimo")
        }
    }

    private fun candidateTokens(
        routeInfo: HttpController.ChatCompletionRouteInfo
    ): List<String> {
        return listOfNotNull(
            routeInfo.requestedModel,
            routeInfo.resolvedModel,
            routeInfo.providerProfileId,
            routeInfo.providerProfileName,
            routeInfo.routeTag,
            routeInfo.apiBase
        ).mapNotNull { value ->
            value.trim()
                .lowercase(Locale.ROOT)
                .takeIf { it.isNotEmpty() }
        }
    }

    private fun buildRouteLabel(
        routeInfo: HttpController.ChatCompletionRouteInfo
    ): String {
        return buildList {
            add("model=${routeInfo.resolvedModel}")
            add("protocol=${routeInfo.protocolType}")
            routeInfo.providerProfileId?.takeIf { it.isNotBlank() }?.let {
                add("profile=$it")
            }
            routeInfo.routeTag?.takeIf { it.isNotBlank() }?.let {
                add("route=$it")
            }
        }.joinToString(separator = ",")
    }
}
