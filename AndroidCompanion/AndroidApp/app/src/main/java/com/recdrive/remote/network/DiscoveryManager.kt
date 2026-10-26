package com.recdrive.remote.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class DiscoveredServer(
    val name: String,
    val host: String,
    val port: Int
)

class DiscoveryManager(context: Context) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val _discoveredServers = MutableStateFlow<List<DiscoveredServer>>(emptyList())
    val discoveredServers: StateFlow<List<DiscoveredServer>> = _discoveredServers.asStateFlow()
    
    private val _isDiscovering = MutableStateFlow(false)
    val isDiscovering: StateFlow<Bool> = _isDiscovering.asStateFlow()

    private var discoveryListener: NsdManager.DiscoveryListener? = null

    fun startDiscovery() {
        if (_isDiscovering.value) return
        _discoveredServers.value = emptyList()

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                _isDiscovering.value = true
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceType.contains("_recdrive-remote")) {
                    resolveService(serviceInfo)
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                _discoveredServers.value = _discoveredServers.value.filter { it.name != serviceInfo.serviceName }
            }

            override fun onDiscoveryStopped(serviceType: String) {
                _isDiscovering.value = false
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                _isDiscovering.value = false
                try { nsdManager.stopServiceDiscovery(this) } catch (_: Exception) {}
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                _isDiscovering.value = false
            }
        }

        try {
            nsdManager.discoverServices("_recdrive-remote._tcp", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (_: Exception) {
            _isDiscovering.value = false
        }
    }

    private fun resolveService(serviceInfo: NsdServiceInfo) {
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}

            override fun onServiceResolved(resolvedInfo: NsdServiceInfo) {
                val hostAddress = resolvedInfo.host?.hostAddress ?: return
                val port = resolvedInfo.port
                val name = resolvedInfo.serviceName ?: "Mac"

                val server = DiscoveredServer(name = name, host = hostAddress, port = port)
                val current = _discoveredServers.value.toMutableList()
                if (current.none { it.host == server.host && it.port == server.port }) {
                    current.add(server)
                    _discoveredServers.value = current
                }
            }
        }

        try {
            nsdManager.resolveService(serviceInfo, resolveListener)
        } catch (_: Exception) {}
    }

    fun stopDiscovery() {
        discoveryListener?.let {
            try {
                nsdManager.stopServiceDiscovery(it)
            } catch (_: Exception) {}
            discoveryListener = null
        }
        _isDiscovering.value = false
    }
}
typealias Bool = Boolean
