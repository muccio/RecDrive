import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// Resilient, auto-recovering microphone capture engine for macOS.
/// Captures audio from any selected or system default input device via AVAudioEngine,
/// automatically recovers across audio route changes (e.g. AirPods battery expiration, Bluetooth/USB disconnects),
/// fills audio gaps with silence to maintain 100% lip-sync alignment with video,
/// and transforms PCM audio buffers into CMSampleBuffer instances with strictly monotonic presentation timestamps.
public final class MicrophoneEngine: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var isRunning = false
    private var isReconnecting = false
    private let lock = NSLock()
    
    private var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
    public private(set) var sampleRate: Double = 48000.0
    public private(set) var channelCount: Int = 2
    
    private var preferredDeviceUID: String?
    private var activeDeviceName: String = "Predefinito"
    private var configObserver: NSObjectProtocol?
    private var isDeviceListenerInstalled = false
    private var watchdogTimer: DispatchSourceTimer?
    private var lastBufferTime: Date = Date()
    
    // Timeline continuity trackers
    private var lastEmittedPTS: CMTime = .invalid
    private var lastEmittedDuration: CMTime = .invalid
    
    private let reconnectQueue = DispatchQueue(label: "com.recdrive.mic.reconnect", qos: .userInitiated)
    
    public init() {}
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Audio Input Devices Discovery
    
    /// Returns all available hardware audio input devices on macOS.
    public static func availableInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultDeviceID = AudioDeviceID(0)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propSize,
            &defaultDeviceID
        )
        
        propertyAddress.mSelector = kAudioHardwarePropertyDevices
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }
        
        var results: [AudioInputDevice] = []
        
        for devID in deviceIDs {
            // Check if device has input streams
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let sStatus = AudioObjectGetPropertyDataSize(devID, &streamAddr, 0, nil, &streamSize)
            guard sStatus == noErr, streamSize > 0 else { continue }
            
            // Query Device Name
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let nStatus = withUnsafeMutablePointer(to: &cfName) { ptr in
                AudioObjectGetPropertyData(devID, &nameAddr, 0, nil, &nameSize, ptr)
            }
            let name: String
            if nStatus == noErr, let str = cfName?.takeRetainedValue() as String? {
                name = str
            } else {
                name = "Microfono (\(devID))"
            }
            
            // Query Device UID
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let uStatus = withUnsafeMutablePointer(to: &cfUID) { ptr in
                AudioObjectGetPropertyData(devID, &uidAddr, 0, nil, &uidSize, ptr)
            }
            let uid: String
            if uStatus == noErr, let str = cfUID?.takeRetainedValue() as String? {
                uid = str
            } else {
                uid = "\(devID)"
            }
            
            results.append(AudioInputDevice(
                id: uid,
                deviceID: devID,
                name: name,
                isDefault: devID == defaultDeviceID
            ))
        }
        
        return results
    }
    
    /// Returns the localized name of the current default audio input device.
    public static func currentDefaultDeviceName() -> String {
        let devices = availableInputDevices()
        if let defaultDev = devices.first(where: { $0.isDefault }) {
            return defaultDev.name
        }
        return devices.first?.name ?? "Microfono di sistema"
    }
    
    // MARK: - Start Capture
    
    /// Start microphone audio capture with automatic resilience and optional device selection.
    public func startCapture(preferredDeviceUID: String? = nil, handler: @escaping (CMSampleBuffer) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        
        if isRunning {
            stopCaptureLocked()
        }
        
        self.preferredDeviceUID = preferredDeviceUID
        self.onAudioSampleBuffer = handler
        self.lastEmittedPTS = .invalid
        self.lastEmittedDuration = .invalid
        self.lastBufferTime = Date()
        
        try setupAndStartEngineLocked()
        self.isRunning = true
        
        // 1. Observe AVAudioEngineConfigurationChange notifications
        installNotificationObservers()
        
        // 2. Observe CoreAudio default device changes
        installCoreAudioListener()
        
        // 3. Start self-healing watchdog timer
        startWatchdogTimer()
    }
    
    /// Convenience backward-compatible startCapture
    public func startCapture(handler: @escaping (CMSampleBuffer) -> Void) throws {
        try startCapture(preferredDeviceUID: nil, handler: handler)
    }
    
    // MARK: - Engine Setup
    
    private func setupAndStartEngineLocked() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Configure specific device if requested
        if let targetUID = preferredDeviceUID, !targetUID.isEmpty {
            let devices = Self.availableInputDevices()
            if let matched = devices.first(where: { $0.id == targetUID }) {
                setInputDevice(matched.deviceID, on: inputNode)
                self.activeDeviceName = matched.name
            } else {
                print("[MicrophoneEngine] Preferred device UID '\(targetUID)' not found. Falling back to system default.")
                self.activeDeviceName = Self.currentDefaultDeviceName()
            }
        } else {
            self.activeDeviceName = Self.currentDefaultDeviceName()
        }
        
        let hwFormat = inputNode.inputFormat(forBus: 0)
        let outputBusFormat = inputNode.outputFormat(forBus: 0)
        let tapFormat = (outputBusFormat.sampleRate > 0 && outputBusFormat.channelCount > 0) ? outputBusFormat : hwFormat
        
        guard tapFormat.sampleRate > 0 && tapFormat.channelCount > 0 else {
            throw NSError(domain: "RecDrive.MicEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Formato di input del microfono '\(activeDeviceName)' non valido (sampleRate: \(tapFormat.sampleRate))."])
        }
        
        // Standardize output to 48000 Hz, Stereo, Float32 for seamless mixing and AAC encoding
        let outSampleRate: Double = 48000.0
        let outChannels: AVAudioChannelCount = 2
        
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outSampleRate,
            channels: outChannels,
            interleaved: false
        ) else {
            throw NSError(domain: "RecDrive.MicEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Impossibile creare il formato audio di destinazione per il microfono."])
        }
        
        let converter = AVAudioConverter(from: tapFormat, to: targetFormat)
        self.audioConverter = converter
        self.sampleRate = outSampleRate
        self.channelCount = Int(outChannels)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: tapFormat) { [weak self] (buffer, when) in
            guard let self = self else { return }
            self.processMicrophoneBuffer(buffer: buffer, when: when, targetFormat: targetFormat)
        }
        
        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        
        print("[MicrophoneEngine] Started capture on '\(activeDeviceName)' (in: \(tapFormat.sampleRate)Hz/\(tapFormat.channelCount)ch -> out: \(outSampleRate)Hz/\(outChannels)ch)")
    }
    
    private func setInputDevice(_ deviceID: AudioDeviceID, on inputNode: AVAudioInputNode) {
        if let audioUnit = inputNode.audioUnit {
            var devID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                print("[MicrophoneEngine] Failed to assign deviceID \(deviceID) to inputNode: \(status)")
            }
        }
    }
    
    // MARK: - Stop Capture
    
    public func stopCapture() {
        lock.lock()
        defer { lock.unlock() }
        stopCaptureLocked()
    }
    
    private func stopCaptureLocked() {
        isRunning = false
        isReconnecting = false
        onAudioSampleBuffer = nil
        
        stopWatchdogTimer()
        removeNotificationObservers()
        removeCoreAudioListener()
        
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        audioEngine = nil
        audioConverter = nil
        lastEmittedPTS = .invalid
        lastEmittedDuration = .invalid
    }
    
    // MARK: - Auto-Healing & Reconnection
    
    fileprivate func handleRouteOrConfigurationChange() {
        lock.lock()
        guard isRunning, !isReconnecting else {
            lock.unlock()
            return
        }
        isReconnecting = true
        lock.unlock()
        
        reconnectQueue.async { [weak self] in
            guard let self = self else { return }
            print("[MicrophoneEngine] Audio route/configuration change detected! Initiating automatic recovery...")
            self.performReconnection()
        }
    }
    
    private func performReconnection() {
        // Attempt recovery up to 5 times with progressive backoff to allow CoreAudio to settle
        let maxAttempts = 5
        var succeeded = false
        
        for attempt in 1...maxAttempts {
            lock.lock()
            guard isRunning else {
                lock.unlock()
                return
            }
            lock.unlock()
            
            // Brief pause to let CoreAudio establish new default or device route
            let delayMs = 150 * attempt
            Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
            
            lock.lock()
            if let oldEngine = audioEngine {
                oldEngine.inputNode.removeTap(onBus: 0)
                oldEngine.stop()
                oldEngine.reset()
                self.audioEngine = nil
            }
            
            do {
                try setupAndStartEngineLocked()
                self.isReconnecting = false
                self.lastBufferTime = Date()
                succeeded = true
                lock.unlock()
                print("[MicrophoneEngine] Recovery successful on attempt \(attempt)/\(maxAttempts) using '\(activeDeviceName)'.")
                break
            } catch {
                lock.unlock()
                print("[MicrophoneEngine] Recovery attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
            }
        }
        
        if !succeeded {
            lock.lock()
            self.isReconnecting = false
            lock.unlock()
            print("[MicrophoneEngine] WARNING: Failed to recover microphone after \(maxAttempts) attempts. Watchdog will keep monitoring.")
        }
    }
    
    // MARK: - Watchdog Timer
    
    private func startWatchdogTimer() {
        stopWatchdogTimer()
        let timer = DispatchSource.makeTimerSource(queue: reconnectQueue)
        timer.schedule(deadline: .now() + 2.5, repeating: 2.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let running = self.isRunning
            let reconnecting = self.isReconnecting
            let lastTime = self.lastBufferTime
            let engineAlive = self.audioEngine?.isRunning ?? false
            self.lock.unlock()
            
            guard running && !reconnecting else { return }
            
            let timeSinceLastBuffer = Date().timeIntervalSince(lastTime)
            if timeSinceLastBuffer > 3.5 || !engineAlive {
                print("[MicrophoneEngine] Watchdog alert: Stalled or stopped engine detected (inactive for \(String(format: "%.1f", timeSinceLastBuffer))s, engineRunning: \(engineAlive)). Recovering...")
                self.handleRouteOrConfigurationChange()
            }
        }
        timer.resume()
        self.watchdogTimer = timer
    }
    
    private func stopWatchdogTimer() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }
    
    // MARK: - Notification Observers
    
    private func installNotificationObservers() {
        removeNotificationObservers()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleRouteOrConfigurationChange()
        }
    }
    
    private func removeNotificationObservers() {
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }
    }
    
    // MARK: - CoreAudio Default Input Device Listener
    
    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    private func installCoreAudioListener() {
        guard !isDeviceListenerInstalled else { return }
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultDeviceAddress,
            audioHardwarePropertyListener,
            clientData
        )
        if status == noErr {
            isDeviceListenerInstalled = true
        } else {
            print("[MicrophoneEngine] Failed to add CoreAudio default device listener: \(status)")
        }
    }
    
    private func removeCoreAudioListener() {
        guard isDeviceListenerInstalled else { return }
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultDeviceAddress,
            audioHardwarePropertyListener,
            clientData
        )
        isDeviceListenerInstalled = false
    }
    
    // MARK: - Buffer Conversion & Silence Gap Filling
    
    private func processMicrophoneBuffer(buffer: AVAudioPCMBuffer, when: AVAudioTime, targetFormat: AVAudioFormat) {
        lock.lock()
        guard isRunning, let handler = onAudioSampleBuffer else {
            lock.unlock()
            return
        }
        let converter = self.audioConverter
        self.lastBufferTime = Date()
        lock.unlock()
        
        let pcmBufferToUse: AVAudioPCMBuffer
        if let converter = converter, buffer.format != targetFormat {
            let ratio = targetFormat.sampleRate / max(buffer.format.sampleRate, 1.0)
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                return
            }
            
            var error: NSError?
            var didProvideInput = false
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if didProvideInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                outStatus.pointee = .haveData
                return buffer
            }
            
            guard status != .error, error == nil, convertedBuffer.frameLength > 0 else {
                return
            }
            pcmBufferToUse = convertedBuffer
        } else {
            pcmBufferToUse = buffer
        }
        
        // Compute presentation timestamp aligned with CoreMedia host time clock
        let pts: CMTime
        if when.isHostTimeValid && when.hostTime > 0 {
            pts = CMClockMakeHostTimeFromSystemUnits(when.hostTime)
        } else {
            pts = CMClockGetTime(CMClockGetHostTimeClock())
        }
        
        lock.lock()
        // Gap Detection & Silence Insertion
        if lastEmittedPTS.isValid, lastEmittedDuration.isValid {
            let expectedPTS = lastEmittedPTS + lastEmittedDuration
            let gapSeconds = CMTimeGetSeconds(pts - expectedPTS)
            
            if gapSeconds > 0.05 && gapSeconds < 10.0 {
                // Gap of 50ms up to 10s: insert silence frames to preserve perfect timeline lip-sync
                let missingFrames = AVAudioFrameCount(gapSeconds * sampleRate)
                if missingFrames > 0, let silenceBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: missingFrames) {
                    silenceBuffer.frameLength = missingFrames
                    // Zero-fill all channels
                    if let channels = silenceBuffer.floatChannelData {
                        for ch in 0..<Int(targetFormat.channelCount) {
                            memset(channels[ch], 0, Int(missingFrames) * MemoryLayout<Float>.size)
                        }
                    }
                    if let silenceSampleBuffer = createSampleBuffer(from: silenceBuffer, presentationTime: expectedPTS) {
                        lock.unlock()
                        handler(silenceSampleBuffer)
                        lock.lock()
                        lastEmittedPTS = expectedPTS
                        lastEmittedDuration = CMTime(value: CMTimeValue(missingFrames), timescale: CMTimeScale(sampleRate))
                    }
                }
            }
        }
        
        // Ensure strictly monotonic PTS
        let finalPTS: CMTime
        if lastEmittedPTS.isValid, lastEmittedDuration.isValid {
            let minPTS = lastEmittedPTS + CMTime(value: 1, timescale: CMTimeScale(sampleRate))
            finalPTS = (pts < minPTS) ? minPTS : pts
        } else {
            finalPTS = pts
        }
        
        let frameDuration = CMTime(value: CMTimeValue(pcmBufferToUse.frameLength), timescale: CMTimeScale(pcmBufferToUse.format.sampleRate))
        self.lastEmittedPTS = finalPTS
        self.lastEmittedDuration = frameDuration
        lock.unlock()
        
        guard let sampleBuffer = createSampleBuffer(from: pcmBufferToUse, presentationTime: finalPTS) else {
            return
        }
        handler(sampleBuffer)
    }
    
    private func createSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        let audioBufferList = pcmBuffer.audioBufferList
        let streamDesc = pcmBuffer.format.streamDescription
        
        var formatDesc: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: streamDesc,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard status == noErr, let format = formatDesc else { return nil }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(pcmBuffer.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let sampleCount = CMItemCount(pcmBuffer.frameLength)
        var sampleSize = max(1, Int(streamDesc.pointee.mBytesPerFrame))
        
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let createdBuffer = sampleBuffer else { return nil }
        
        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            createdBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        )
        guard setStatus == noErr else { return nil }
        
        return createdBuffer
    }
}

// MARK: - CoreAudio C Callback Function

private func audioHardwarePropertyListener(
    _ inObjectID: AudioObjectID,
    _ inNumberAddresses: UInt32,
    _ inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }
    let engine = Unmanaged<MicrophoneEngine>.fromOpaque(clientData).takeUnretainedValue()
    engine.handleRouteOrConfigurationChange()
    return noErr
}
