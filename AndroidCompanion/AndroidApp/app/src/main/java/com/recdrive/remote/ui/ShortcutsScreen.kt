package com.recdrive.remote.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.VolumeDown
import androidx.compose.material.icons.filled.VolumeMute
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.recdrive.remote.network.ConnectionManager
import com.recdrive.remote.network.RemoteCommand

@Composable
fun ShortcutsScreen(connectionManager: ConnectionManager) {
    val view = LocalView.current
    var inputText by remember { mutableStateOf("") }
    val scrollState = rememberScrollState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Text Input & Send
        Text(
            text = "Digitazione Testo su Mac",
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF9CA3AF)
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = inputText,
                onValueChange = { inputText = it },
                placeholder = { Text("Digita testo o usa la voce...") },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Color(0xFF007AFF),
                    unfocusedBorderColor = Color(0xFF2E3440),
                    focusedContainerColor = Color(0xFF161920),
                    unfocusedContainerColor = Color(0xFF161920),
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White
                ),
                maxLines = 2
            )

            Spacer(modifier = Modifier.size(8.dp))

            ElevatedButton(
                onClick = {
                    if (inputText.isNotEmpty()) {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        connectionManager.sendCommand(RemoteCommand.text(inputText))
                        inputText = ""
                    }
                },
                modifier = Modifier.height(56.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.elevatedButtonColors(
                    containerColor = Color(0xFF007AFF),
                    contentColor = Color.White
                )
            ) {
                Icon(Icons.Default.Send, contentDescription = "Invia")
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        // Audio & Media Controls
        Text(
            text = "Audio & Media",
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF9CA3AF)
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ShortcutButton(
                label = "Vol +",
                icon = { Icon(Icons.Default.VolumeUp, contentDescription = null, modifier = Modifier.size(18.dp)) },
                modifier = Modifier.weight(1f)
            ) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("volume_up"))
            }

            ShortcutButton(
                label = "Vol -",
                icon = { Icon(Icons.Default.VolumeDown, contentDescription = null, modifier = Modifier.size(18.dp)) },
                modifier = Modifier.weight(1f)
            ) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("volume_down"))
            }

            ShortcutButton(
                label = "Muto",
                icon = { Icon(Icons.Default.VolumeMute, contentDescription = null, modifier = Modifier.size(18.dp)) },
                modifier = Modifier.weight(1f)
            ) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("mute"))
            }

            ShortcutButton(
                label = "Play/Pausa",
                icon = { Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp)) },
                modifier = Modifier.weight(1f)
            ) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("play_pause"))
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        // Navigation Keys
        Text(
            text = "Tasti di Navigazione",
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF9CA3AF)
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ShortcutButton(label = "Spazio", modifier = Modifier.weight(1f)) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("space"))
            }

            ShortcutButton(label = "Invio", modifier = Modifier.weight(1f)) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("enter"))
            }

            ShortcutButton(label = "Tab", modifier = Modifier.weight(1f)) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("tab"))
            }

            ShortcutButton(label = "Esc", modifier = Modifier.weight(1f)) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("escape"))
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        // System & Multi-Tasking Shortcuts
        Text(
            text = "Sistema & Finestre macOS",
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF9CA3AF)
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ShortcutButton(label = "⌘ Tab (App)", modifier = Modifier.weight(1f)) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("app_switch"))
            }

            ShortcutButton(label = "Mission Control", modifier = Modifier.weight(1f)) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("mission_control"))
            }

            ShortcutButton(label = "⌘ Spazio", modifier = Modifier.weight(1f)) {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                connectionManager.sendCommand(RemoteCommand.shortcut("spotlight"))
            }
        }
    }
}

@Composable
private fun ShortcutButton(
    label: String,
    icon: (@Composable () -> Unit)? = null,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    ElevatedButton(
        onClick = onClick,
        modifier = modifier.height(48.dp),
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.elevatedButtonColors(
            containerColor = Color(0xFF1E232B),
            contentColor = Color.White
        ),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 6.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            if (icon != null) {
                icon()
                Spacer(modifier = Modifier.size(4.dp))
            }
            Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}
