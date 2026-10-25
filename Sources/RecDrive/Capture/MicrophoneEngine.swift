import Foundation
import AVFoundation
import CoreAudio

/// Captures audio from the default input device (microphone) via AVAudioEngine
/// and transforms PCM audio buffers into CMSampleBuffer instances with accurate presentation timestamps.
public final class MicrophoneEngine: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var isRunning = false
    private let lock = NSLock()
    
    private var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
    public private(set) var sampleRate: Double = 48000.0
    public private(set) var channelCount: Int = 1
    
    public init() {}
    
    public func startCapture(handler: @escaping (CMSampleBuffer) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        
        if isRunning {
            stopCaptureLocked()
        }
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)
        let outputBusFormat = inputNode.outputFormat(forBus: 0)
        let tapFormat = (outputBusFormat.sampleRate > 0 && outputBusFormat.channelCount > 0) ? outputBusFormat : hwFormat
        
        guard tapFormat.sampleRate > 0 && tapFormat.channelCount > 0 else {
            throw NSError(domain: "RecDrive.MicEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Formato di input del microfono non valido."])
        }
        
        let outSampleRate: Double = 48000.0
        let outChannels: AVAudioChannelCount = min(max(tapFormat.channelCount, 1), 2)
        
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: outSampleRate,
            channels: outChannels,
            interleaved: true
        ) else {
            throw NSError(domain: "RecDrive.MicEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Impossibile creare il formato PCM per il microfono."])
        }
        
        let converter = AVAudioConverter(from: tapFormat, to: targetFormat)
        self.audioConverter = converter
        self.sampleRate = outSampleRate
        self.channelCount = Int(outChannels)
        self.onAudioSampleBuffer = handler
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: tapFormat) { [weak self] (buffer, when) in
            guard let self = self else { return }
            self.processMicrophoneBuffer(buffer: buffer, when: when, targetFormat: targetFormat)
        }
        
        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        self.isRunning = true
    }
    
    public func stopCapture() {
        lock.lock()
        defer { lock.unlock() }
        stopCaptureLocked()
    }
    
    private func stopCaptureLocked() {
        onAudioSampleBuffer = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        audioEngine = nil
        audioConverter = nil
        isRunning = false
    }
    
    // MARK: - Buffer Conversion to CMSampleBuffer
    
    private func processMicrophoneBuffer(buffer: AVAudioPCMBuffer, when: AVAudioTime, targetFormat: AVAudioFormat) {
        lock.lock()
        guard isRunning, let handler = onAudioSampleBuffer else {
            lock.unlock()
            return
        }
        let converter = self.audioConverter
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
        
        guard let sampleBuffer = createSampleBuffer(from: pcmBufferToUse, presentationTime: when) else {
            return
        }
        handler(sampleBuffer)
    }
    
    private func createSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, presentationTime: AVAudioTime) -> CMSampleBuffer? {
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
        
        // Compute presentation timestamp aligned with CoreMedia host time clock
        let pts: CMTime
        if presentationTime.isHostTimeValid && presentationTime.hostTime > 0 {
            pts = CMClockMakeHostTimeFromSystemUnits(presentationTime.hostTime)
        } else {
            pts = CMClockGetTime(CMClockGetHostTimeClock())
        }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(pcmBuffer.format.sampleRate)),
            presentationTimeStamp: pts,
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
