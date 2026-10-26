package com.recdrive.remote.network

import com.google.gson.annotations.SerializedName

/**
 * Data model for remote commands sent to the Mac receiver over TCP.
 */
data class RemoteCommand(
    @SerializedName("type") val type: String,
    @SerializedName("action") val action: String? = null,
    @SerializedName("code") val code: Int? = null,
    @SerializedName("modifiers") val modifiers: List<String>? = null,
    @SerializedName("name") val name: String? = null,
    @SerializedName("dx") val dx: Double? = null,
    @SerializedName("dy") val dy: Double? = null,
    @SerializedName("button") val button: String? = null,
    @SerializedName("text") val text: String? = null,
    @SerializedName("timestamp") val timestamp: Double? = null
) {
    companion object {
        // Presentation Actions
        fun nextSlide() = RemoteCommand(type = "presentation", action = "next")
        fun prevSlide() = RemoteCommand(type = "presentation", action = "prev")
        fun playSlideshow() = RemoteCommand(type = "presentation", action = "play")
        fun exitSlideshow() = RemoteCommand(type = "presentation", action = "escape")
        fun blackScreen() = RemoteCommand(type = "presentation", action = "black_screen")
        fun whiteScreen() = RemoteCommand(type = "presentation", action = "white_screen")
        
        // Direct Key & Shortcut Actions
        fun key(code: Int, modifiers: List<String>? = null) = RemoteCommand(type = "key", code = code, modifiers = modifiers)
        fun shortcut(name: String) = RemoteCommand(type = "shortcut", name = name)
        
        // Mouse Actions
        fun mouseMove(dx: Double, dy: Double) = RemoteCommand(type = "mouse_move", dx = dx, dy = dy)
        fun mouseClick(button: String = "left") = RemoteCommand(type = "mouse_click", button = button)
        fun mouseScroll(dx: Double, dy: Double) = RemoteCommand(type = "mouse_scroll", dx = dx, dy = dy)
        
        // Text Input
        fun text(text: String) = RemoteCommand(type = "text", text = text)
        
        // Ping
        fun ping() = RemoteCommand(type = "ping", timestamp = System.currentTimeMillis() / 1000.0)
    }
}

/**
 * Server reply received from Mac.
 */
data class ServerResponse(
    @SerializedName("type") val type: String,
    @SerializedName("message") val message: String? = null,
    @SerializedName("serverName") val serverName: String? = null,
    @SerializedName("timestamp") val timestamp: Double? = null
)
