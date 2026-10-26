package com.recdrive.remote.network

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket

sealed class ConnectionState {
    object Disconnected : ConnectionState()
    object Connecting : ConnectionState()
    data class Connected(val host: String, val port: Int, val serverName: String? = null) : ConnectionState()
    data class Error(val message: String) : ConnectionState()
}

class ConnectionManager private constructor(context: Context) {
    private val scope = CoroutineScope(Dispatchers.IO + Job())
    private val gson = Gson()
    private val prefs: SharedPreferences = context.getSharedPreferences("RecDriveRemotePrefs", Context.MODE_PRIVATE)
    
    private var socket: Socket? = null
    private var writer: BufferedWriter? = null
    private var reader: BufferedReader? = null
    private var readJob: Job? = null
    private var pingJob: Job? = null
    
    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()
    
    private val _latencyMs = MutableStateFlow<Long?>(null)
    val latencyMs: StateFlow<Long?> = _latencyMs.asStateFlow()
    
    var lastSavedHost: String
        get() = prefs.getString("saved_host", "192.168.1.") ?: "192.168.1."
        set(value) = prefs.edit().putString("saved_host", value).apply()
        
    var lastSavedPort: Int
        get() = prefs.getInt("saved_port", 19850)
        set(value) = prefs.edit().putInt("saved_port", value).apply()

    fun connect(host: String, port: Int = 19850) {
        if (_connectionState.value is ConnectionState.Connecting) return
        
        lastSavedHost = host
        lastSavedPort = port
        _connectionState.value = ConnectionState.Connecting
        
        scope.launch {
            try {
                disconnectInternal()
                
                val newSocket = Socket()
                newSocket.connect(InetSocketAddress(host, port), 4000) // 4 sec timeout
                newSocket.tcpNoDelay = true
                newSocket.keepAlive = true
                
                socket = newSocket
                writer = BufferedWriter(OutputStreamWriter(newSocket.getOutputStream(), Charsets.UTF_8))
                reader = BufferedReader(InputStreamReader(newSocket.getInputStream(), Charsets.UTF_8))
                
                _connectionState.value = ConnectionState.Connected(host, port)
                
                startReading()
                startPingLoop()
                
                // Send initial ping to get server name
                sendCommand(RemoteCommand.ping())
            } catch (e: Exception) {
                disconnectInternal()
                _connectionState.value = ConnectionState.Error("Connessione fallita: ${e.localizedMessage ?: "Timeout"}")
            }
        }
    }

    fun disconnect() {
        scope.launch {
            disconnectInternal()
            _connectionState.value = ConnectionState.Disconnected
        }
    }

    private fun disconnectInternal() {
        readJob?.cancel()
        readJob = null
        pingJob?.cancel()
        pingJob = null
        
        try { writer?.close() } catch (_: Exception) {}
        try { reader?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        
        writer = null
        reader = null
        socket = null
        _latencyMs.value = null
    }

    fun sendCommand(command: RemoteCommand) {
        scope.launch {
            try {
                val currentWriter = writer ?: return@launch
                val json = gson.toJson(command)
                currentWriter.write(json)
                currentWriter.write("\n")
                currentWriter.flush()
            } catch (e: Exception) {
                disconnectInternal()
                _connectionState.value = ConnectionState.Error("Disconnesso durante l'invio: ${e.localizedMessage}")
            }
        }
    }

    private fun startReading() {
        readJob = scope.launch {
            try {
                val currentReader = reader ?: return@launch
                while (isActive) {
                    val line = currentReader.readLine() ?: break
                    if (line.isNotEmpty()) {
                        handleIncomingLine(line)
                    }
                }
            } catch (_: Exception) {
            } finally {
                if (isActive) {
                    disconnectInternal()
                    _connectionState.value = ConnectionState.Disconnected
                }
            }
        }
    }

    private fun handleIncomingLine(line: String) {
        try {
            val response = gson.fromJson(line, ServerResponse::class.java)
            if (response.type == "pong") {
                if (response.timestamp != null) {
                    val now = System.currentTimeMillis() / 1000.0
                    val latency = ((now - response.timestamp) * 1000).toLong()
                    _latencyMs.value = maxOf(1L, latency)
                }
                val current = _connectionState.value
                if (current is ConnectionState.Connected) {
                    _connectionState.value = current.copy(serverName = response.serverName)
                }
            }
        } catch (_: Exception) {}
    }

    private fun startPingLoop() {
        pingJob = scope.launch {
            while (isActive) {
                delay(5000)
                if (_connectionState.value is ConnectionState.Connected) {
                    sendCommand(RemoteCommand.ping())
                }
            }
        }
    }

    companion object {
        @Volatile
        private var instance: ConnectionManager? = null

        fun getInstance(context: Context): ConnectionManager {
            return instance ?: synchronized(this) {
                instance ?: ConnectionManager(context.applicationContext).also { instance = it }
            }
        }
    }
}
