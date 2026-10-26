package com.recdrive.remote

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Mouse
import androidx.compose.material.icons.filled.Slideshow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import com.recdrive.remote.network.ConnectionState
import com.recdrive.remote.network.DiscoveryManager
import com.recdrive.remote.ui.ConnectionDialog
import com.recdrive.remote.ui.PresentationScreen
import com.recdrive.remote.ui.RemoteTheme
import com.recdrive.remote.ui.ShortcutsScreen
import com.recdrive.remote.ui.TrackpadScreen

class MainActivity : ComponentActivity() {
    private lateinit var connectionManager: ConnectionManager
    private lateinit var discoveryManager: DiscoveryManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        connectionManager = ConnectionManager.getInstance(this)
        discoveryManager = DiscoveryManager(this)

        // Try auto-connecting to last saved host if valid
        val lastHost = connectionManager.lastSavedHost
        if (lastHost.isNotBlank() && !lastHost.endsWith(".")) {
            connectionManager.connect(lastHost, connectionManager.lastSavedPort)
        }

        setContent {
            RemoteTheme {
                MainContent(
                    connectionManager = connectionManager,
                    discoveryManager = discoveryManager
                )
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        discoveryManager.stopDiscovery()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainContent(
    connectionManager: ConnectionManager,
    discoveryManager: DiscoveryManager
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    var showConnectionDialog by remember { mutableStateOf(false) }

    val connectionState by connectionManager.connectionState.collectAsState()
    val latencyMs by connectionManager.latencyMs.collectAsState()

    if (showConnectionDialog) {
        ConnectionDialog(
            connectionManager = connectionManager,
            discoveryManager = discoveryManager,
            onDismiss = { showConnectionDialog = false }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "RecDrive Remote",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )

                        Spacer(modifier = Modifier.weight(1f))

                        // Connection Status Pill Button
                        ConnectionStatusPill(
                            state = connectionState,
                            latencyMs = latencyMs,
                            onClick = { showConnectionDialog = true }
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color(0xFF0F1115)
                )
            )
        },
        bottomBar = {
            NavigationBar(
                containerColor = Color(0xFF0F1115),
                contentColor = Color.White
            ) {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    icon = { Icon(Icons.Default.Slideshow, contentDescription = "Slide") },
                    label = { Text("Slide") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Color(0xFF007AFF),
                        selectedTextColor = Color(0xFF007AFF),
                        indicatorColor = Color(0xFF1E293B),
                        unselectedIconColor = Color(0xFF64748B),
                        unselectedTextColor = Color(0xFF64748B)
                    )
                )

                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    icon = { Icon(Icons.Default.Mouse, contentDescription = "Mouse") },
                    label = { Text("Mouse") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Color(0xFF007AFF),
                        selectedTextColor = Color(0xFF007AFF),
                        indicatorColor = Color(0xFF1E293B),
                        unselectedIconColor = Color(0xFF64748B),
                        unselectedTextColor = Color(0xFF64748B)
                    )
                )

                NavigationBarItem(
                    selected = selectedTab == 2,
                    onClick = { selectedTab = 2 },
                    icon = { Icon(Icons.Default.Keyboard, contentDescription = "Comandi") },
                    label = { Text("Comandi") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Color(0xFF007AFF),
                        selectedTextColor = Color(0xFF007AFF),
                        indicatorColor = Color(0xFF1E293B),
                        unselectedIconColor = Color(0xFF64748B),
                        unselectedTextColor = Color(0xFF64748B)
                    )
                )
            }
        },
        containerColor = Color(0xFF0A0C0E)
    ) { innerPadding ->
        Surface(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            color = Color(0xFF0A0C0E)
        ) {
            when (selectedTab) {
                0 -> PresentationScreen(connectionManager)
                1 -> TrackpadScreen(connectionManager)
                2 -> ShortcutsScreen(connectionManager)
            }
        }
    }
}

@Composable
private fun ConnectionStatusPill(
    state: ConnectionState,
    latencyMs: Long?,
    onClick: () -> Unit
) {
    val (dotColor, text) = when (state) {
        is ConnectionState.Connected -> {
            val serverName = state.serverName ?: "Mac"
            val latencyStr = if (latencyMs != null) " (${latencyMs}ms)" else ""
            Color(0xFF34C759) to "$serverName$latencyStr"
        }
        is ConnectionState.Connecting -> Color(0xFFFF9500) to "Connessione..."
        is ConnectionState.Disconnected -> Color(0xFFFF3B30) to "Disconnesso"
        is ConnectionState.Error -> Color(0xFFFF3B30) to "Errore"
    }

    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Color(0xFF1E232B))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(dotColor)
        )
        Spacer(modifier = Modifier.size(6.dp))
        Text(
            text = text,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White
        )
    }
}
