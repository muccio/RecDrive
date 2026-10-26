package com.recdrive.remote.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.recdrive.remote.network.ConnectionManager
import com.recdrive.remote.network.DiscoveryManager

@Composable
fun ConnectionDialog(
    connectionManager: ConnectionManager,
    discoveryManager: DiscoveryManager,
    onDismiss: () -> Unit
) {
    var hostInput by remember { mutableStateOf(connectionManager.lastSavedHost) }
    var portInput by remember { mutableStateOf(connectionManager.lastSavedPort.toString()) }
    val discoveredServers by discoveryManager.discoveredServers.collectAsState()
    val isDiscovering by discoveryManager.isDiscovering.collectAsState()

    DisposableEffect(Unit) {
        discoveryManager.startDiscovery()
        onDispose {
            discoveryManager.stopDiscovery()
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(text = "Connessione al Mac", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Bonjour Discovered Macs section
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Mac Rilevati (Wi-Fi):",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(0xFF9CA3AF)
                    )
                    IconButton(
                        onClick = {
                            discoveryManager.stopDiscovery()
                            discoveryManager.startDiscovery()
                        },
                        modifier = Modifier.size(28.dp)
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = "Ricarica", tint = Color(0xFF007AFF))
                    }
                }

                if (discoveredServers.isEmpty()) {
                    Text(
                        text = if (isDiscovering) "Ricerca in corso sulla rete locale..." else "Nessun Mac trovato via Bonjour.",
                        fontSize = 12.sp,
                        color = Color(0xFF6B7280)
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(110.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        items(discoveredServers) { server ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(Color(0xFF222732))
                                    .clickable {
                                        connectionManager.connect(server.host, server.port)
                                        onDismiss()
                                    }
                                    .padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(Icons.Default.Computer, contentDescription = null, tint = Color(0xFF007AFF))
                                Spacer(modifier = Modifier.size(8.dp))
                                Column {
                                    Text(server.name, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
                                    Text("${server.host}:${server.port}", fontSize = 11.sp, color = Color(0xFF9CA3AF))
                                }
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(6.dp))

                // Manual IP input section
                Text(
                    text = "Oppure Inserisci Indirizzo IP Manualmente:",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color(0xFF9CA3AF)
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = hostInput,
                        onValueChange = { hostInput = it },
                        label = { Text("IP Mac") },
                        placeholder = { Text("es. 192.168.1.50") },
                        modifier = Modifier.weight(2f),
                        singleLine = true
                    )

                    OutlinedTextField(
                        value = portInput,
                        onValueChange = { portInput = it },
                        label = { Text("Porta") },
                        modifier = Modifier.weight(1f),
                        singleLine = true
                    )
                }

                Text(
                    text = "💡 Suggerimento: Se connesso via cavo USB con adb puoi usare: adb forward tcp:19850 tcp:19850 e connetterti a 127.0.0.1",
                    fontSize = 11.sp,
                    color = Color(0xFF6B7280)
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val port = portInput.toIntOrNull() ?: 19850
                    connectionManager.connect(hostInput.trim(), port)
                    onDismiss()
                },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF007AFF))
            ) {
                Text("Connetti")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Annulla", color = Color(0xFF9CA3AF))
            }
        }
    )
}
