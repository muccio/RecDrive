package com.recdrive.remote.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AdsClick
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.recdrive.remote.network.ConnectionManager
import com.recdrive.remote.network.RemoteCommand

@Composable
fun TrackpadScreen(connectionManager: ConnectionManager) {
    val view = LocalView.current
    var sensitivity by remember { mutableFloatStateOf(1.8f) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Trackpad Surface (fills most of the space)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(20.dp))
                .background(Color(0xFF161920))
                .pointerInput(sensitivity) {
                    detectTapGestures(
                        onTap = {
                            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            connectionManager.sendCommand(RemoteCommand.mouseClick("left"))
                        },
                        onDoubleTap = {
                            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            connectionManager.sendCommand(RemoteCommand.mouseClick("double"))
                        },
                        onLongPress = {
                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            connectionManager.sendCommand(RemoteCommand.mouseClick("right"))
                        }
                    )
                }
                .pointerInput(sensitivity) {
                    detectDragGestures { change, dragAmount ->
                        change.consume()
                        val dx = (dragAmount.x * sensitivity).toDouble()
                        val dy = (dragAmount.y * sensitivity).toDouble()
                        connectionManager.sendCommand(RemoteCommand.mouseMove(dx, dy))
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    imageVector = Icons.Default.TouchApp,
                    contentDescription = "Trackpad",
                    modifier = Modifier.size(48.dp),
                    tint = Color.White.copy(alpha = 0.25f)
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Trackpad Mac",
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "Trascina per muovere • Tocca per cliccare • Tieni premuto per tasto destro",
                    color = Color.White.copy(alpha = 0.25f),
                    fontSize = 11.sp,
                    modifier = Modifier.padding(horizontal = 24.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }
        }

        // Sensitivity slider
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Sensibilità:", fontSize = 12.sp, color = Color(0xFF9CA3AF))
            Spacer(modifier = Modifier.size(8.dp))
            Slider(
                value = sensitivity,
                onValueChange = { sensitivity = it },
                valueRange = 0.8f..3.5f,
                modifier = Modifier.weight(1f),
                colors = SliderDefaults.colors(
                    thumbColor = Color(0xFF007AFF),
                    activeTrackColor = Color(0xFF007AFF),
                    inactiveTrackColor = Color(0xFF222730)
                )
            )
            Spacer(modifier = Modifier.size(8.dp))
            Text(String.format("%.1fx", sensitivity), fontSize = 12.sp, color = Color.White, fontWeight = FontWeight.Bold)
        }

        // Dedicated Physical Mouse Click Buttons (Left / Scroll / Right)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            ElevatedButton(
                onClick = {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    connectionManager.sendCommand(RemoteCommand.mouseClick("left"))
                },
                modifier = Modifier
                    .weight(1.2f)
                    .height(56.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.elevatedButtonColors(
                    containerColor = Color(0xFF252A34),
                    contentColor = Color.White
                )
            ) {
                Text("Click Sinistro", fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }

            // Scroll Up / Down
            Row(
                modifier = Modifier
                    .weight(0.9f)
                    .height(56.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                ElevatedButton(
                    onClick = {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        connectionManager.sendCommand(RemoteCommand.mouseScroll(0.0, 30.0))
                    },
                    modifier = Modifier.weight(1f).height(56.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.elevatedButtonColors(
                        containerColor = Color(0xFF1F242D),
                        contentColor = Color.White
                    ),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)
                ) {
                    Text("▲", fontSize = 16.sp)
                }

                ElevatedButton(
                    onClick = {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        connectionManager.sendCommand(RemoteCommand.mouseScroll(0.0, -30.0))
                    },
                    modifier = Modifier.weight(1f).height(56.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.elevatedButtonColors(
                        containerColor = Color(0xFF1F242D),
                        contentColor = Color.White
                    ),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)
                ) {
                    Text("▼", fontSize = 16.sp)
                }
            }

            ElevatedButton(
                onClick = {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    connectionManager.sendCommand(RemoteCommand.mouseClick("right"))
                },
                modifier = Modifier
                    .weight(1.2f)
                    .height(56.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.elevatedButtonColors(
                    containerColor = Color(0xFF252A34),
                    contentColor = Color.White
                )
            ) {
                Text("Click Destro", fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}
