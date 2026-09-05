package com.kundi.kundi_mobile.tts

import java.net.URI

object SpeechEndpoint {
    fun isRegional(endpoint: String, region: String): Boolean {
        val uri = URI(endpoint)
        require(
            uri.scheme == "https" &&
                uri.userInfo == null &&
                uri.port == -1 &&
                uri.query == null &&
                uri.fragment == null &&
                uri.path in listOf("", "/")
        )
        val regional = uri.host == "$region.api.cognitive.microsoft.com"
        require(
            regional ||
                Regex("[a-z0-9][a-z0-9-]*\\.cognitiveservices\\.azure\\.com")
                    .matches(uri.host ?: "")
        )
        return regional
    }

    fun websocket(endpoint: String) = URI("wss://${URI(endpoint).host}")
}
