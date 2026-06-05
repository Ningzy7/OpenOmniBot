package cn.com.omnimind.bot.webchat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRunRequestNormalizerTest {
    @Test
    fun `explicit userMessage and attachments win over content blocks`() {
        val normalized = AgentRunRequestNormalizer.normalize(
            mapOf(
                "userMessage" to "explicit",
                "attachments" to listOf(
                    mapOf("url" to "https://example.com/a.png", "isImage" to true)
                ),
                "content" to listOf(
                    mapOf("type" to "text", "text" to "ignored"),
                    mapOf(
                        "type" to "image_url",
                        "image_url" to mapOf("url" to "data:image/png;base64,IGNORED")
                    )
                )
            )
        )

        assertEquals("explicit", normalized.userMessage)
        assertEquals(1, normalized.attachments.size)
        assertEquals(
            "https://example.com/a.png",
            normalized.attachments.single()["url"]
        )
    }

    @Test
    fun `content blocks are converted into text plus image attachments`() {
        val normalized = AgentRunRequestNormalizer.normalize(
            mapOf(
                "content" to listOf(
                    mapOf("type" to "text", "text" to "请分析"),
                    mapOf(
                        "type" to "image_url",
                        "image_url" to mapOf(
                            "url" to "data:image/png;base64,AAAA"
                        )
                    )
                )
            )
        )

        assertEquals("请分析", normalized.userMessage)
        assertEquals(1, normalized.attachments.size)
        assertEquals(true, normalized.attachments.single()["isImage"])
        assertEquals(
            "data:image/png;base64,AAAA",
            normalized.attachments.single()["dataUrl"]
        )
    }

    @Test
    fun `messages fallback uses the latest user message content blocks`() {
        val normalized = AgentRunRequestNormalizer.normalize(
            mapOf(
                "messages" to listOf(
                    mapOf("role" to "user", "content" to "旧问题"),
                    mapOf("role" to "assistant", "content" to "旧回答"),
                    mapOf(
                        "role" to "user",
                        "content" to listOf(
                            mapOf("type" to "text", "text" to "新问题"),
                            mapOf(
                                "type" to "image_url",
                                "url" to "https://example.com/new.png"
                            )
                        )
                    )
                )
            )
        )

        assertEquals("新问题", normalized.userMessage)
        assertEquals(1, normalized.attachments.size)
        assertEquals(
            "https://example.com/new.png",
            normalized.attachments.single()["url"]
        )
        assertTrue(normalized.attachments.single()["fileName"].toString().startsWith("image_"))
    }

    @Test
    fun `attachment blocks preserve file semantics instead of being coerced into images`() {
        val normalized = AgentRunRequestNormalizer.normalize(
            mapOf(
                "content" to listOf(
                    mapOf("type" to "text", "text" to "check this file"),
                    mapOf(
                        "type" to "attachment",
                        "name" to "ezfpy_documentation.md",
                        "path" to "/storage/emulated/0/ezfpy_documentation.md",
                        "mimeType" to "text/markdown"
                    )
                )
            )
        )

        assertEquals("check this file", normalized.userMessage)
        assertEquals(1, normalized.attachments.size)
        assertEquals(false, normalized.attachments.single()["isImage"])
        assertEquals(
            "/storage/emulated/0/ezfpy_documentation.md",
            normalized.attachments.single()["path"]
        )
        assertEquals(
            "text/markdown",
            normalized.attachments.single()["mimeType"]
        )
    }
}
